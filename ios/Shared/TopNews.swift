import Foundation

/// 위젯이 보여 주는 주요 뉴스 요약. 앱이 분석을 받을 때마다 SharedBox에 써 두고,
/// 위젯은 토큰이 있으면 직접 새로 받고 실패하면 이 값을 쓴다.
struct TopNews: Codable, Sendable {
    struct Item: Codable, Sendable, Identifiable, Hashable {
        let id: Int
        let rank: Int
        let title: String
        let summary: String?
        let countries: [String]
        let articles: Int
        let sources: Int
    }
    let analyzedAt: Date
    let items: [Item]

    static func load() -> TopNews? { SharedBox.codable("topnews") }
    func save() { SharedBox.setCodable("topnews", self) }

    static let placeholder = TopNews(analyzedAt: .now, items: [
        .init(id: 0, rank: 1, title: "세계 주요 뉴스를 불러오는 중", summary: "여러 나라 언론이 함께 다룬 사건을 1시간마다 정리합니다.",
              countries: ["KR", "US", "JP"], articles: 120, sources: 40),
        .init(id: 1, rank: 2, title: "두 번째 사건", summary: nil, countries: ["GB", "DE"], articles: 80, sources: 30),
        .init(id: 2, rank: 3, title: "세 번째 사건", summary: nil, countries: ["CN"], articles: 50, sources: 20),
        .init(id: 3, rank: 4, title: "네 번째 사건", summary: nil, countries: ["FR"], articles: 40, sources: 15),
        .init(id: 4, rank: 5, title: "다섯 번째 사건", summary: nil, countries: ["IN"], articles: 30, sources: 10),
    ])
}

/// 위젯·앱 공용: 최신 주요 뉴스만 가볍게 받는다(표본 기사 없이).
enum TopNewsFetcher {
    private struct Digest: Decodable {
        struct Event: Decodable {
            let id: Int
            let rank: Int
            let title: String?
            let summary: String?
            let countries: [String]
            let articles: Int
            let sources: Int
        }
        let createdAt: Date
        let events: [Event]
    }

    static func fetch(_ account: Account) async throws -> TopNews {
        var c = URLComponents(url: account.apiBase.appending(path: "digest/latest"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "samples", value: "0"), URLQueryItem(name: "lang", value: "ko")]
        var req = URLRequest(url: c.url!, timeoutInterval: 15)
        req.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let d = try JSONDecoder.meridian.decode(Digest.self, from: data)
        return TopNews(analyzedAt: d.createdAt, items: d.events.prefix(5).map {
            .init(id: $0.id, rank: $0.rank, title: $0.title ?? "제목 정리 중", summary: $0.summary,
                  countries: $0.countries, articles: $0.articles, sources: $0.sources)
        })
    }
}

/// 국기 이모지(웹과 같은 표)
enum Flag {
    static let map: [String: String] = [
        "KR": "🇰🇷", "KP": "🇰🇵", "US": "🇺🇸", "CN": "🇨🇳", "JP": "🇯🇵", "RU": "🇷🇺", "TW": "🇹🇼", "GB": "🇬🇧",
        "DE": "🇩🇪", "FR": "🇫🇷", "IN": "🇮🇳", "UA": "🇺🇦", "IL": "🇮🇱", "IR": "🇮🇷", "INTL": "🌐",
    ]
    static func of(_ code: String) -> String { map[code.uppercased()] ?? "🏳️" }
    static func row(_ codes: [String], max: Int = 6) -> String {
        let s = codes.prefix(max).map(of).joined()
        return codes.count > max ? s + " +\(codes.count - max)" : s
    }
}
