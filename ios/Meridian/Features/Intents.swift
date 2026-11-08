import AppIntents
import Foundation

/// Siri·단축어: "자오선 주요 뉴스 알려줘" — 앱을 열지 않고 상위 세 건을 말해 준다.
struct TopNewsIntent: AppIntent {
    static let title: LocalizedStringResource = "주요 뉴스 알려 주기"
    static let description = IntentDescription("최근 24시간 여러 나라 언론이 함께 다룬 사건 상위 세 건을 알려 줍니다.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        var top = TopNews.load()
        if let a = Account.load(), let fresh = try? await TopNewsFetcher.fetch(a) {
            fresh.save()
            top = fresh
        }
        guard let top, !top.items.isEmpty else {
            return .result(value: "", dialog: "아직 받은 주요 뉴스가 없어요. 자오선을 한 번 열어 주세요.")
        }
        let lines = top.items.prefix(3).map { "\($0.rank)위, \($0.title)" }
        let text = lines.joined(separator: ". ")
        return .result(value: text, dialog: IntentDialog(stringLiteral: "지금 주요 뉴스입니다. " + text + "."))
    }
}

/// 단축어: 검색어로 자오선 검색 화면 열기
struct SearchNewsIntent: AppIntent {
    static let title: LocalizedStringResource = "뉴스 검색"
    static let description = IntentDescription("자오선을 열고 검색어로 기사를 찾습니다.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "검색어")
    var query: String

    func perform() async throws -> some IntentResult {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        PendingLink.set("meridian://search?q=\(q)")
        return .result()
    }
}

struct MeridianShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TopNewsIntent(),
                    phrases: ["\(.applicationName) 주요 뉴스 알려줘", "\(.applicationName)에서 오늘 뉴스", "\(.applicationName) 헤드라인"],
                    shortTitle: "주요 뉴스", systemImageName: "globe.asia.australia")
        AppShortcut(intent: OpenBriefingIntent(),
                    phrases: ["\(.applicationName) 브리핑 들려줘", "\(.applicationName)로 뉴스 듣기"],
                    shortTitle: "브리핑 듣기", systemImageName: "headphones")
        AppShortcut(intent: SearchNewsIntent(),
                    phrases: ["\(.applicationName)에서 뉴스 검색"],
                    shortTitle: "뉴스 검색", systemImageName: "magnifyingglass")
    }
}
