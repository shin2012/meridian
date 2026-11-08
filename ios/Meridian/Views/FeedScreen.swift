import SwiftUI

/// 기사 목록(시간순, 커서로 이어 받기). 국가·언론사·주제·검색·북마크 모두 이 화면을 쓴다.
struct FeedScreen: View {
    @Environment(NewsStore.self) private var store
    let filter: FeedFilter
    var embedded = false              // 다른 화면 안(검색 결과 등)에 들어갈 때 제목·새로고침은 바깥이 맡는다
    @State private var items: [ArticleItem] = []
    @State private var cursor: String?? = .none     // nil=처음, .some(nil)=끝
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            OfflineBanner().frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Color.clear)
            ForEach(visible) { a in
                NavigationLink(value: Route.article(a.id)) { ArticleRow(item: a) }
                    .articleActions(a)
                    .onAppear { if a.id == visible.last?.id { Task { await more() } } }
            }
            if loading { LoadingRow() }
            else if case .some(.none) = cursor, items.isEmpty {
                ContentUnavailableView(filter.bookmarked ? "북마크한 기사가 없어요" : "기사가 없습니다",
                                       systemImage: filter.bookmarked ? "bookmark" : "newspaper",
                                       description: Text(filter.bookmarked ? "기사를 왼쪽으로 밀어 북마크해 보세요." : ""))
                    .listRowSeparator(.hidden)
            } else if case .some(.none) = cursor, !items.isEmpty {
                Text("끝").font(.footnote).foregroundStyle(.tertiary).frame(maxWidth: .infinity).listRowSeparator(.hidden)
            }
            if let error, items.isEmpty { Text(error).foregroundStyle(.secondary) }
        }
        .listStyle(.plain)
        .navigationTitle(embedded ? "" : filter.title)
        .refreshable { await Task { await reload() }.value }
        .task(id: filter) { await reload() }
        .onChange(of: items) { _, v in store.requestTitles(v) }
    }

    private var visible: [ArticleItem] {
        var v = items
        if store.ui.hideRead && !filter.bookmarked { v = v.filter { !store.isRead($0) } }
        if filter.bookmarked { v = v.filter { store.isBookmarked($0) } }
        return v
    }

    private var query: [String: String?] {
        [
            "country": filter.country, "source": filter.source, "topic": filter.topic, "q": filter.query,
            "bookmarked": filter.bookmarked ? "true" : nil,
            "body_only": store.ui.bodyOnly && !filter.bookmarked ? "true" : nil,
            "lang": store.lang, "limit": "40",
        ]
    }

    private func reload() async {
        if items.isEmpty, let c: ArticlePage = store.cached("articles", query) {
            items = c.items
        }
        cursor = .none
        await page(reset: true)
    }

    private func more() async {
        guard !loading, case .some(.some(_)) = cursor else { return }
        await page(reset: false)
    }

    private func page(reset: Bool) async {
        loading = true
        defer { loading = false }
        var q = query
        if !reset, case .some(.some(let c)) = cursor { q["cursor"] = c }
        do {
            let p: ArticlePage = try await store.fetch("articles", q)
            if reset { items = p.items } else {
                let have = Set(items.map(\.id))
                items += p.items.filter { !have.contains($0.id) }
            }
            cursor = .some(p.nextCursor)
            error = nil
        } catch {
            if !APIError.isCancel(error) && !APIError.isOffline(error) { self.error = error.localizedDescription }
            if reset && items.isEmpty { cursor = .some(nil) }
        }
    }
}

/// 검색(탭 막대의 검색 칸)
struct SearchScreen: View {
    @Environment(Router.self) private var router
    @Environment(NewsStore.self) private var store
    @State private var submitted = ""

    var body: some View {
        @Bindable var router = router
        SwiftUI.Group {
            if submitted.isEmpty {
                List {
                    Section("최근 많이 다룬 사건") {
                        ForEach(store.digest?.top ?? []) { e in
                            Button { router.searchText = e.displayTitle; submitted = e.displayTitle } label: {
                                Label(e.displayTitle, systemImage: "sparkle.magnifyingglass")
                            }
                        }
                    }
                    Section("주제") {
                        ForEach(store.topics) { t in
                            NavigationLink(value: Route.feed(FeedFilter(title: t.key, topic: t.key))) {
                                LabeledContent(t.key, value: "24시간 \(t.articles24h.grouped)건")
                            }
                        }
                    }
                }
            } else {
                FeedScreen(filter: FeedFilter(title: "“\(submitted)” 검색 결과", query: submitted), embedded: true)
            }
        }
        .navigationTitle(submitted.isEmpty ? "검색" : "“\(submitted)”")
        .searchable(text: $router.searchText, prompt: "제목·요약·본문 검색")
        .onSubmit(of: .search) { submitted = router.searchText.trimmingCharacters(in: .whitespaces) }
        .onChange(of: router.searchText) { _, v in if v.isEmpty { submitted = "" } }
        .onAppear { if !router.searchText.isEmpty { submitted = router.searchText } }
    }
}
