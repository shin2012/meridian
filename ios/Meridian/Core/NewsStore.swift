import CoreSpotlight
import Foundation
import Observation
import Translation
import WidgetKit

/// 앱 전체 상태. 화면은 먼저 디스크에 있는 마지막 응답을 그리고, 네트워크에서 새로 받아 바꾼다.
@MainActor @Observable
final class NewsStore {
    static let shared = NewsStore()

    var account: Account? = Account.load()
    var ui = UiSettings()
    var countries: [Country] = []
    var topics: [Topic] = []
    var digest: Digest?
    var offline = false
    var lastError: String?

    /// 북마크·읽음은 누르는 즉시 모든 목록에 반영(서버 반영은 outbox가 이어서)
    var bookmarkOverride: [Int: Bool] = [:]
    var readOverride: [Int: Bool] = [:]
    /// 목록 제목·요약 번역(서버 /translate/items)
    var translatedTitles: [Int: TranslatedItem] = [:]

    private var outbox: [Pending] = []
    private var trWaiting: Set<Int> = []
    private var trTask: Task<Void, Never>?

    struct Pending: Codable, Hashable { let method: String; let path: String }

    var api: API? { account.map(API.init) }
    var isConfigured: Bool { account != nil }

    init() {
        if let d = UserDefaults.standard.data(forKey: "outbox"), let o = try? JSONDecoder().decode([Pending].self, from: d) {
            outbox = o
        }
        if let s: SettingsDoc = DiskCache.decode(DiskCache.key("settings", [:])) { ui = s.ui ?? UiSettings() }
        countries = DiskCache.decode(DiskCache.key("countries", [:])) ?? []
        topics = DiskCache.decode(DiskCache.key("topics", [:])) ?? []
        digest = DiskCache.decode(DiskCache.key("digest/latest", digestQuery))
    }

    struct SettingsDoc: Codable { var ui: UiSettings? }

    /// 번역 엔진(이 기기에만 저장): 서버(Claude 우선) 또는 아이폰 기본 번역(Apple 번역, 기기 안에서)
    enum TrEngine: String, CaseIterable, Sendable { case server, device }
    var trEngine: TrEngine = TrEngine(rawValue: UserDefaults.standard.string(forKey: "trEngine") ?? "") ?? .server {
        didSet {
            guard oldValue != trEngine else { return }
            UserDefaults.standard.set(trEngine.rawValue, forKey: "trEngine")
            translatedTitles = [:]
            deviceBusy = []
            deviceMissing = []
        }
    }
    private var deviceBusy: Set<Int> = []
    private var deviceMissing: Set<String> = []     // 언어팩이 없어 기기 번역이 안 되는 언어(서버로 넘김)

    /// 목록 요청에 붙이는 번역 언어. 기기 번역이면 서버 번역본을 받지 않고 원문을 받아 기기에서 옮긴다.
    var lang: String? { ui.translate && trEngine == .server ? "ko" : nil }
    var digestQuery: [String: String?] { ["samples": "4", "lang": "ko"] }

    // MARK: 연결

    func connect(_ a: Account) async throws {
        let api = API(account: a)
        _ = try await api.data("GET", "topics")
        Account.save(a)
        account = a
        await refreshAll()
        Push.shared.sync()
    }

    func disconnect() {
        Account.save(nil)
        account = nil
        DiskCache.clear()
        digest = nil
        countries = []
        topics = []
    }

    // MARK: 공통 받기

    /// 캐시 → (네트워크) 순서. 실패하면 캐시를 그대로 두고 offline 표시만.
    func cached<T: Decodable>(_ path: String, _ query: [String: String?] = [:], as: T.Type = T.self) -> T? {
        DiskCache.decode(DiskCache.key(path, query))
    }

    func fetch<T: Decodable>(_ path: String, _ query: [String: String?] = [:], as: T.Type = T.self) async throws -> T {
        guard let api else { throw APIError.notConfigured }
        do {
            let (v, raw): (T, Data) = try await api.get(path, query: query)
            DiskCache.write(DiskCache.key(path, query), raw)
            offline = false
            return v
        } catch {
            if APIError.isOffline(error) { offline = true }
            throw error
        }
    }

    func refreshAll() async {
        guard isConfigured else { return }
        await flushOutbox()
        async let s: Void = refreshSettings()
        async let c: Void = refreshCountries()
        async let t: Void = refreshTopics()
        async let d = refreshDigest()
        _ = await (s, c, t, d)
        DiskCache.prune()
    }

    func refreshSettings() async {
        if let s: SettingsDoc = try? await fetch("settings") { ui = s.ui ?? UiSettings() }
    }

    func refreshCountries() async {
        if let c: [Country] = try? await fetch("countries") { countries = c }
    }

    func refreshTopics() async {
        if let t: [Topic] = try? await fetch("topics") { topics = t }
    }

    @discardableResult
    func refreshDigest() async -> Bool {
        do {
            let d: Digest = try await fetch("digest/latest", digestQuery)
            let changed = d.id != digest?.id
            digest = d
            lastError = nil
            publishWidget(d)
            if changed { Task { await prefetchTopStories(d) } }
            return changed
        } catch {
            if !APIError.isCancel(error) && !APIError.isOffline(error) { lastError = error.localizedDescription }
            return false
        }
    }

    func saveUi(_ next: UiSettings) {
        ui = next
        struct Body: Encodable { let ui: UiSettings }
        if let raw = try? JSONEncoder.meridian.encode(SettingsDoc(ui: next)) {
            DiskCache.write(DiskCache.key("settings", [:]), raw)
        }
        Task { _ = try? await api?.send("PUT", "settings", body: Body(ui: next)) }
    }

    /// 보이는 국가(설정의 순서·숨김 반영)
    var visibleCountries: [Country] {
        let order = ui.order.isEmpty ? countries.map(\.code) : ui.order
        let by = Dictionary(uniqueKeysWithValues: countries.map { ($0.code, $0) })
        let sorted = order.filter { by[$0] != nil } + countries.map(\.code).filter { !order.contains($0) }
        return sorted.compactMap { by[$0] }.filter { !ui.hidden.contains($0.code) }
    }

    func countryName(_ code: String) -> String {
        countries.first { $0.code == code }?.nameKo ?? code
    }

    // MARK: 기사

    func detailKey(_ id: Int) -> String { DiskCache.key("articles/\(id)", ["lang": "ko"]) }

    func cachedDetail(_ id: Int) -> ArticleDetail? { DiskCache.decode(detailKey(id)) }

    func detail(_ id: Int) async throws -> ArticleDetail {
        try await fetch("articles/\(id)", ["lang": "ko"])
    }

    /// 서버 번역(저장본이 있으면 바로). 성공하면 상세 캐시도 번역본으로 바꾼다.
    func serverTranslate(_ id: Int) async throws -> ArticleDetail {
        guard let api else { throw APIError.notConfigured }
        let raw = try await api.data("POST", "articles/\(id)/translate", query: ["lang": "ko"], timeout: 120)
        DiskCache.write(detailKey(id), raw)
        return try JSONDecoder.meridian.decode(ArticleDetail.self, from: raw)
    }

    func serverSummary(_ id: Int) async throws -> ServerSummary {
        let key = DiskCache.key("articles/\(id)/summary", [:])
        if let s: ServerSummary = DiskCache.decode(key) { return s }
        guard let api else { throw APIError.notConfigured }
        let raw = try await api.data("POST", "articles/\(id)/summary", query: ["lang": "ko"], timeout: 90)
        DiskCache.write(key, raw)
        return try JSONDecoder.meridian.decode(ServerSummary.self, from: raw)
    }

    /// 주요 뉴스 표본 기사의 본문을 미리 받아 둔다(지하철·비행기에서도 읽게)
    func prefetchTopStories(_ d: Digest) async {
        let ids = d.top.flatMap { $0.samples.map(\.id) }
        for id in ids where cachedDetail(id) == nil {
            _ = try? await detail(id)
        }
    }

    func apply(_ a: ArticleItem) -> ArticleItem {
        var a = a
        if let b = bookmarkOverride[a.id] { a.bookmarked = b }
        if let r = readOverride[a.id] { a.read = r }
        if ui.translate, a.needsTranslation, let t = translatedTitles[a.id], let title = t.title {
            a.title = title
            a.summary = t.summary ?? a.summary
            a.translated = true
        }
        return a
    }

    func isBookmarked(_ a: ArticleItem) -> Bool { bookmarkOverride[a.id] ?? a.bookmarked }
    func isRead(_ a: ArticleItem) -> Bool { readOverride[a.id] ?? a.read }

    func setBookmark(_ a: ArticleItem, _ on: Bool) {
        bookmarkOverride[a.id] = on
        enqueue(Pending(method: on ? "PUT" : "DELETE", path: "bookmarks/\(a.id)"))
        Spotlight.index(a, bookmarked: on)
    }

    func setRead(_ a: ArticleItem, _ on: Bool) {
        guard isRead(a) != on else { return }
        readOverride[a.id] = on
        enqueue(Pending(method: on ? "PUT" : "DELETE", path: "read/\(a.id)"))
    }

    private func enqueue(_ p: Pending) {
        // 같은 기사·같은 종류의 이전 요청은 지운다(마지막 상태만 보내면 됨)
        let base = p.path
        outbox.removeAll { $0.path == base }
        outbox.append(p)
        saveOutbox()
        Task { await flushOutbox() }
    }

    private func saveOutbox() {
        UserDefaults.standard.set(try? JSONEncoder().encode(outbox), forKey: "outbox")
    }

    func flushOutbox() async {
        guard let api, !outbox.isEmpty else { return }
        for p in outbox {
            do {
                _ = try await api.data(p.method, p.path)
                outbox.removeAll { $0 == p }
            } catch {
                if APIError.isOffline(error) { offline = true; break }
                outbox.removeAll { $0 == p }      // 서버가 거절한 요청은 다시 보내지 않는다
            }
        }
        saveOutbox()
    }

    var pendingCount: Int { outbox.count }

    // MARK: 목록 번역(웹과 같이 400ms 모아서 한 번에)

    func requestTitles(_ items: [ArticleItem]) {
        guard ui.translate, isConfigured else { return }
        var items = items
        if trEngine == .device {
            items = deviceTitles(items)       // 언어팩이 없는 언어만 서버로
            if items.isEmpty { return }
        }
        let ids = items.filter { $0.needsTranslation && translatedTitles[$0.id] == nil }.map(\.id)
        guard !ids.isEmpty else { return }
        trWaiting.formUnion(ids)
        guard trTask == nil else { return }          // 보내는 중이면 반복문이 이어서 보낸다
        trTask = Task {
            defer { trTask = nil }
            try? await Task.sleep(for: .milliseconds(400))
            struct Body: Encodable { let ids: [Int] }
            while !trWaiting.isEmpty {
                let batch = Array(trWaiting.prefix(200))
                trWaiting.subtract(batch)
                guard let api, let raw = try? await api.send("POST", "translate/items", body: Body(ids: batch)),
                      let got = try? JSONDecoder.meridian.decode([TranslatedItem].self, from: raw) else { return }
                for t in got { translatedTitles[t.id] = t }
            }
        }
    }

    /// 아이폰 기본 번역으로 목록 제목·요약을 옮긴다. 언어팩이 없는 언어의 기사는 돌려줘서 서버가 번역하게 한다.
    private func deviceTitles(_ items: [ArticleItem]) -> [ArticleItem] {
        let todo = items.filter { $0.needsTranslation && translatedTitles[$0.id] == nil && !deviceBusy.contains($0.id) }
        let missing = todo.filter { deviceMissing.contains($0.language ?? "") || ($0.language ?? "").isEmpty }
        let mine = todo.filter { !(deviceMissing.contains($0.language ?? "") || ($0.language ?? "").isEmpty) }
        guard !mine.isEmpty else { return missing }
        deviceBusy.formUnion(mine.map(\.id))
        let groups = Dictionary(grouping: mine) { $0.language ?? "" }
        Task {
            for (code, list) in groups {
                var reqs: [TranslationSession.Request] = []
                for a in list {
                    if let t = a.title, !t.isEmpty { reqs.append(.init(sourceText: t, clientIdentifier: "t\(a.id)")) }
                    if let s = a.summary, !s.isEmpty { reqs.append(.init(sourceText: s, clientIdentifier: "s\(a.id)")) }
                }
                let session = TranslationSession(installedSource: Locale.Language(identifier: code),
                                                 target: Locale.Language(identifier: "ko"))
                do {
                    let res = try await session.translations(from: reqs)
                    var title: [Int: String] = [:], sum: [Int: String] = [:]
                    for r in res {
                        guard let k = r.clientIdentifier, let id = Int(k.dropFirst()) else { continue }
                        if k.hasPrefix("t") { title[id] = r.targetText } else { sum[id] = r.targetText }
                    }
                    for a in list { translatedTitles[a.id] = TranslatedItem(id: a.id, title: title[a.id], summary: sum[a.id]) }
                } catch {
                    // 언어팩 없음 등 → 이 언어는 서버 번역으로
                    deviceMissing.insert(code)
                    deviceBusy.subtract(list.map(\.id))
                    requestTitles(list)
                }
            }
        }
        return missing
    }

    /// 기사 화면에서 기기 번역이 성공하면(언어팩을 받았을 수 있음) 그 언어를 다시 기기 번역 대상으로
    func deviceLanguageReady(_ code: String?) {
        if let code { deviceMissing.remove(code) }
    }

    // MARK: 위젯

    func publishWidget(_ d: Digest) {
        let top = TopNews(analyzedAt: d.createdAt, items: d.top.map {
            .init(id: $0.id, rank: $0.rank, title: $0.displayTitle, summary: $0.summary,
                  countries: $0.countries, articles: $0.articles, sources: $0.sources)
        })
        top.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
