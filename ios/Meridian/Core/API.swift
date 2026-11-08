import CryptoKit
import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case unauthorized
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "서버 연결 정보가 없습니다. 설정에서 서버 주소와 앱 토큰을 넣어 주세요."
        case .unauthorized: "앱 토큰이 맞지 않습니다. 설정에서 토큰을 확인해 주세요."
        case .http(let code, let msg): code == 429 ? "요청이 많습니다. 잠시 뒤 다시 시도해 주세요." : "서버 오류 \(code): \(msg)"
        }
    }

    static func isOffline(_ e: Error) -> Bool {
        if let u = e as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                    .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff].contains(u.code)
        }
        return false
    }

    static func isCancel(_ e: Error) -> Bool {
        e is CancellationError || (e as? URLError)?.code == .cancelled
    }
}

/// /app/v1 클라이언트. 모든 요청에 Bearer 앱 토큰.
struct API: Sendable {
    let account: Account

    static var current: API? { Account.load().map(API.init) }

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 25
        c.waitsForConnectivity = false
        c.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20)   // 기사 사진 캐시
        return URLSession(configuration: c)
    }()

    func url(_ path: String, _ query: [String: String?] = [:]) -> URL {
        var c = URLComponents(url: account.apiBase.appending(path: path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }.sorted { $0.name < $1.name }
        c.queryItems = items.isEmpty ? nil : items
        return c.url!
    }

    func data(_ method: String = "GET", _ path: String, query: [String: String?] = [:], body: Data? = nil,
              timeout: TimeInterval = 25) async throws -> Data {
        var req = URLRequest(url: url(path, query), timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await API.session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(code) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw APIError.http(code, msg ?? String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        return data
    }

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:], as: T.Type = T.self) async throws -> (T, Data) {
        let d = try await data("GET", path, query: query)
        return (try JSONDecoder.meridian.decode(T.self, from: d), d)
    }

    func send<B: Encodable>(_ method: String, _ path: String, body: B, query: [String: String?] = [:]) async throws -> Data {
        try await data(method, path, query: query, body: try JSONEncoder().encode(body), timeout: 120)
    }
}

/// 받은 응답을 그대로 디스크에 둔다(오프라인에서도 마지막 화면을 보여 주기 위해).
/// 키 = 경로+쿼리. 원본 JSON을 저장하므로 서버에 새 필드가 생겨도 옮길 것이 없다.
enum DiskCache {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appending(path: "Meridian/cache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        var v = d
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        try? v.setResourceValues(rv)
        return d
    }()
    static let limitBytes = 300 << 20

    static func key(_ path: String, _ query: [String: String?]) -> String {
        let q = query.compactMap { k, v in v.map { "\(k)=\($0)" } }.sorted().joined(separator: "&")
        return path + "?" + q
    }

    private static func file(_ key: String) -> URL {
        let h = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return dir.appending(path: String(h.prefix(40)) + ".json")
    }

    static func read(_ key: String) -> Data? { try? Data(contentsOf: file(key)) }

    static func write(_ key: String, _ data: Data) {
        try? data.write(to: file(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func decode<T: Decodable>(_ key: String, as: T.Type = T.self) -> T? {
        read(key).flatMap { try? JSONDecoder.meridian.decode(T.self, from: $0) }
    }

    static func size() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        API.session.configuration.urlCache?.removeAllCachedResponses()
    }

    /// 한도를 넘으면 오래 안 쓴 파일부터 지운다.
    static func prune() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard var files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        var total = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        guard total > limitBytes else { return }
        files.sort {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        for f in files where total > limitBytes * 8 / 10 {
            total -= (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try? FileManager.default.removeItem(at: f)
        }
    }
}
