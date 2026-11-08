import Foundation

// 서버 계약: world-news packages/api-types/openapi.json (/api/v1 = 앱에서는 /app/v1)
// 키는 snake_case → camelCase 자동 변환(JSONDecoder.meridian).

struct SourceRef: Codable, Hashable, Sendable {
    let id: Int
    let slug: String
    let name: String
}

struct ArticleItem: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    var title: String?
    var summary: String?
    let url: String
    let source: SourceRef
    let country: String
    let language: String?
    let publishedAt: Date?
    let sortAt: Date
    let imageUrl: String?
    let bodyStatus: String?
    let paywalled: Bool
    let wordCount: Int?
    var read: Bool
    var bookmarked: Bool
    var translated: Bool
    let topic: String?

    var isForeign: Bool { !(language ?? "ko").hasPrefix("ko") }
    var needsTranslation: Bool { !translated && isForeign }
    var displayTitle: String { (title?.isEmpty == false ? title : nil) ?? "(제목 수집 중)" }

    /// 웹과 같은 본문 상태 표시
    var badge: (text: String, tone: Badge.Tone)? {
        if paywalled || bodyStatus == "partial" { return ("유료·일부", .pay) }
        switch bodyStatus {
        case "summary": return ("요약만", .dim)
        case "none": return ("제목만", .dim)
        case nil: return ("본문 수집 중", .wait)
        default: return nil
        }
    }
}

enum Badge { enum Tone { case pay, dim, wait } }

struct ArticleImage: Codable, Hashable, Sendable {
    let src: String
    var alt: String?
    var at: Double
}

/// 기사 본문(목록 항목 + 본문·사진). 서버 응답은 평평한 객체라 같은 디코더에서 두 번 읽는다.
struct ArticleDetail: Codable, Hashable, Sendable {
    var item: ArticleItem
    let author: String?
    var body: String?
    let extractedBy: String?
    var images: [ArticleImage]

    private enum K: String, CodingKey { case author, body, extractedBy, images }

    init(from decoder: Decoder) throws {
        item = try ArticleItem(from: decoder)
        let c = try decoder.container(keyedBy: K.self)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        extractedBy = try c.decodeIfPresent(String.self, forKey: .extractedBy)
        images = (try? c.decodeIfPresent([ArticleImage].self, forKey: .images)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        try item.encode(to: encoder)
        var c = encoder.container(keyedBy: K.self)
        try c.encodeIfPresent(author, forKey: .author)
        try c.encodeIfPresent(body, forKey: .body)
        try c.encodeIfPresent(extractedBy, forKey: .extractedBy)
        try c.encode(images, forKey: .images)
    }

    var paragraphs: [String] {
        (body ?? "").split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

struct ArticlePage: Codable, Sendable {
    var items: [ArticleItem]
    let nextCursor: String?
}

/// "articles_24h"는 snake_case 변환에서 "articles24H"가 된다(숫자 뒤 글자도 대문자로 바뀜). 두 표기 모두 받는다.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Decoder {
    func count24h() -> Int {
        guard let c = try? container(keyedBy: AnyKey.self) else { return 0 }
        for k in c.allKeys where k.stringValue.lowercased() == "articles24h" {
            return (try? c.decode(Int.self, forKey: k)) ?? 0
        }
        return 0
    }
}

struct Country: Codable, Hashable, Identifiable, Sendable {
    let code: String
    let kind: String?
    let nameKo: String
    let languages: [String]?
    let timezone: String?
    let sources: Int?
    let articles: Int?
    var articles24h: Int = 0
    var id: String { code }

    private enum CodingKeys: String, CodingKey { case code, kind, nameKo, languages, timezone, sources, articles }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        nameKo = (try? c.decode(String.self, forKey: .nameKo)) ?? code
        languages = try? c.decodeIfPresent([String].self, forKey: .languages)
        timezone = try? c.decodeIfPresent(String.self, forKey: .timezone)
        sources = try? c.decodeIfPresent(Int.self, forKey: .sources)
        articles = try? c.decodeIfPresent(Int.self, forKey: .articles)
        articles24h = decoder.count24h()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(code, forKey: AnyKey("code"))
        try c.encodeIfPresent(kind, forKey: AnyKey("kind"))
        try c.encode(nameKo, forKey: AnyKey("name_ko"))
        try c.encodeIfPresent(languages, forKey: AnyKey("languages"))
        try c.encodeIfPresent(timezone, forKey: AnyKey("timezone"))
        try c.encodeIfPresent(sources, forKey: AnyKey("sources"))
        try c.encodeIfPresent(articles, forKey: AnyKey("articles"))
        try c.encode(articles24h, forKey: AnyKey("articles_24h"))
    }
}

struct FeedGroup: Codable, Hashable, Identifiable, Sendable {
    let key: String
    let name: String
    var items: [ArticleItem]
    var id: String { key }
}

struct Topic: Codable, Hashable, Identifiable, Sendable {
    let key: String
    let description: String
    var articles24h: Int = 0
    var id: String { key }

    private enum CodingKeys: String, CodingKey { case key, description }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        articles24h = decoder.count24h()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(key, forKey: AnyKey("key"))
        try c.encode(description, forKey: AnyKey("description"))
        try c.encode(articles24h, forKey: AnyKey("articles_24h"))
    }
}

struct DigestStats: Codable, Hashable, Sendable {
    let articles: Int?
    let shareMultiSource: Double?
    let shareMultiCountry: Double?
    let groupsMultiCountry: Int?
}

struct NewsEvent: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let rank: Int
    let title: String?
    let summary: String?
    let category: String?
    let countries: [String]
    let sources: Int
    let articles: Int
    let firstSeen: Date?
    let lastSeen: Date?
    var samples: [ArticleItem]
    var displayTitle: String { title ?? "제목 정리 중" }
}

struct Digest: Codable, Hashable, Sendable {
    let id: Int
    let createdAt: Date
    let windowFrom: Date
    let windowTo: Date
    let stats: DigestStats
    var events: [NewsEvent]

    var top: [NewsEvent] { Array(events.prefix(5)) }
    var rest: [NewsEvent] { Array(events.dropFirst(5)) }
}

struct TranslatedItem: Codable, Sendable {
    let id: Int
    let title: String?
    let summary: String?
}

struct ServerSummary: Codable, Sendable {
    let articleId: Int
    let summary: String
    let model: String?
    let cached: Bool
}

/// 웹과 같은 보기 설정(서버 settings.ui 에 저장되어 웹·앱이 같이 쓴다)
struct UiSettings: Codable, Equatable, Sendable {
    var defaultView: String = "event"      // event | timeline | country | source | bookmark
    var hidden: [String] = []
    var order: [String] = []
    var fontSize: String = "m"             // s | m | l
    var hideRead: Bool = false
    var bodyOnly: Bool = false
    var translate: Bool = true

    init() {}
    init(from decoder: Decoder) throws {   // 일부 키만 있어도 기본값으로 채운다
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = UiSettings()
        d.defaultView = (try? c.decode(String.self, forKey: .defaultView)) ?? d.defaultView
        d.hidden = (try? c.decode([String].self, forKey: .hidden)) ?? d.hidden
        d.order = (try? c.decode([String].self, forKey: .order)) ?? d.order
        d.fontSize = (try? c.decode(String.self, forKey: .fontSize)) ?? d.fontSize
        d.hideRead = (try? c.decode(Bool.self, forKey: .hideRead)) ?? d.hideRead
        d.bodyOnly = (try? c.decode(Bool.self, forKey: .bodyOnly)) ?? d.bodyOnly
        d.translate = (try? c.decode(Bool.self, forKey: .translate)) ?? d.translate
        self = d
    }
}

struct DevicePrefs: Codable, Equatable, Sendable {
    var topChange = true
    var morning = true
    var quiet = true
    enum CodingKeys: String, CodingKey { case topChange = "top_change", morning, quiet }
}
