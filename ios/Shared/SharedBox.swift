import Foundation
import Security

/// 앱 ↔ 위젯이 같이 쓰는 작은 저장소(키체인 공유 그룹). App Group 등록 없이 자동 서명으로 동작한다.
/// 서버 주소·앱 토큰과 위젯용 주요 뉴스 요약만 넣는다.
enum SharedBox {
    private static let service = "kr.b-612.meridian.shared"
    static var group: String? { Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String }

    static func set(_ key: String, _ data: Data?) {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        if let g = group, !g.hasPrefix("$(") { q[kSecAttrAccessGroup as String] = g }
        SecItemDelete(q as CFDictionary)
        guard let data else { return }
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        #if targetEnvironment(simulator)
        if status != errSecSuccess { UserDefaults.standard.set(data, forKey: "sb." + key) }
        #else
        _ = status
        #endif
    }

    static func get(_ key: String) -> Data? {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        if let g = group, !g.hasPrefix("$(") { q[kSecAttrAccessGroup as String] = g }
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data { return d }
        #if targetEnvironment(simulator)
        return UserDefaults.standard.data(forKey: "sb." + key)
        #else
        return nil
        #endif
    }

    static func setCodable<T: Encodable>(_ key: String, _ value: T?) {
        set(key, value.flatMap { try? JSONEncoder.meridian.encode($0) })
    }

    static func codable<T: Decodable>(_ key: String, as: T.Type = T.self) -> T? {
        get(key).flatMap { try? JSONDecoder.meridian.decode(T.self, from: $0) }
    }
}

/// 서버 연결 정보. 코드·저장소에는 절대 넣지 않고, 기기에서 설정 화면이나 설정 링크로만 받는다.
struct Account: Codable, Equatable, Sendable {
    var server: URL      // 예: https://example.com  (앱 경로 /app/v1 은 붙이지 않는다)
    var token: String

    static func load() -> Account? { SharedBox.codable("account") }
    static func save(_ a: Account?) { SharedBox.setCodable("account", a) }

    var apiBase: URL { server.appending(path: "app/v1") }

    /// 사용자가 붙여 넣은 주소를 정리한다(끝의 / 와 /app/v1 제거, 스킴 없으면 https).
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/app/v1") { s.removeLast(7) }
        guard let u = URL(string: s), u.host() != nil else { return nil }
        return u
    }
}

extension JSONDecoder {
    static let meridian: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let v = MeridianDate.parse(s) { return v }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "날짜 형식 \(s)")
        }
        return d
    }()
}

extension JSONEncoder {
    static let meridian: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

enum MeridianDate {
    nonisolated(unsafe) private static let frac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String) -> Date? {
        if let d = frac.date(from: s) ?? plain.date(from: s) { return d }
        // 시간대 없는 값(서버 naive datetime)은 UTC로 본다
        if !s.hasSuffix("Z"), !s.contains("+") { return frac.date(from: s + "Z") ?? plain.date(from: s + "Z") }
        return nil
    }

    /// "방금 / 5분 전 / 3시간 전 / 2일 전 / 날짜" — 웹과 같은 표기
    static func ago(_ d: Date?, now: Date = .now) -> String {
        guard let d else { return "" }
        let m = Int((now.timeIntervalSince(d) / 60).rounded())
        if m < 1 { return "방금" }
        if m < 60 { return "\(m)분 전" }
        if m < 60 * 24 { return "\(m / 60)시간 전" }
        if m < 60 * 24 * 7 { return "\(m / 1440)일 전" }
        return d.formatted(.dateTime.locale(Locale(identifier: "ko_KR")).year().month().day())
    }
}
