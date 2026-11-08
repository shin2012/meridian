import AppIntents
import Foundation

/// 제어 센터·잠금 화면 버튼과 단축어에서 쓰는 "주요 뉴스 열기". 앱과 위젯 확장 양쪽에 들어간다.
/// 앱이 열리면 SharedBox의 pendingURL을 읽어 해당 화면으로 간다.
struct OpenTopNewsIntent: AppIntent {
    static let title: LocalizedStringResource = "주요 뉴스 열기"
    static let description = IntentDescription("자오선을 열고 전 세계 주요 뉴스를 보여 줍니다.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        PendingLink.set("meridian://digest")
        return .result()
    }
}

struct OpenBriefingIntent: AppIntent {
    static let title: LocalizedStringResource = "주요 뉴스 브리핑 듣기"
    static let description = IntentDescription("자오선을 열고 주요 뉴스 다섯 건을 읽어 줍니다.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        PendingLink.set("meridian://briefing")
        return .result()
    }
}

enum PendingLink {
    static func set(_ s: String) { SharedBox.set("pending", s.data(using: .utf8)) }
    static func take() -> URL? {
        guard let d = SharedBox.get("pending"), let s = String(data: d, encoding: .utf8) else { return nil }
        SharedBox.set("pending", nil)
        return URL(string: s)
    }
}
