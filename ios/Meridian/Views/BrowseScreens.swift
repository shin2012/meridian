import SwiftUI

/// 주제별(칸반): Jev로 분류한 8개 주제. 아이패드는 열을 나란히, 아이폰은 주제를 골라 한 열씩.
struct TopicsScreen: View {
    @Environment(NewsStore.self) private var store
    @Environment(\.horizontalSizeClass) private var hsize
    @State private var country: String?
    @State private var topic: String?

    var body: some View {
        VStack(spacing: 0) {
            ChipBar(items: [(nil, "전체")] + store.visibleCountries.map { (Optional($0.code), "\(Flag.of($0.code)) \($0.nameKo)") },
                    selection: $country)
            if hsize == .regular {
                board
            } else {
                ChipBar(items: store.topics.map { (Optional($0.key), "\($0.key) \($0.articles24h.grouped)") }, selection: $topic)
                if let t = topic ?? store.topics.first?.key {
                    FeedScreen(filter: FeedFilter(title: t, country: country, topic: t), embedded: true)
                } else {
                    LoadingRow()
                    Spacer()
                }
            }
        }
        .navigationTitle("주제별")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var board: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(store.topics) { t in
                    TopicColumn(topic: t, country: country)
                        .frame(width: 320)
                }
            }
            .padding(.horizontal)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }
}

private struct TopicColumn: View {
    @Environment(NewsStore.self) private var store
    let topic: Topic
    let country: String?
    @State private var items: [ArticleItem] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(topic.key).font(.system(.title3, design: .serif).weight(.bold))
                Spacer()
                Text("24시간 \(topic.articles24h.grouped)건").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items.filter { !store.ui.hideRead || !store.isRead($0) }) { a in
                        NavigationLink(value: Route.article(a.id)) {
                            ArticleRow(item: a, compact: true).padding(.horizontal, 14).padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .articleActions(a)
                        Divider().padding(.leading, 14)
                    }
                    if loading { LoadingRow() }
                    NavigationLink(value: Route.feed(FeedFilter(title: topic.key, country: country, topic: topic.key))) {
                        Text("더 보기").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding()
                    }
                }
            }
        }
        .background(.background.secondary, in: .rect(cornerRadius: 20))
        .task(id: country) { await load() }
        .onChange(of: items) { _, v in store.requestTitles(v) }
    }

    private func load() async {
        let q: [String: String?] = ["topic": topic.key, "country": country, "lang": store.lang, "limit": "30",
                                    "body_only": store.ui.bodyOnly ? "true" : nil]
        if let c: ArticlePage = store.cached("articles", q) { items = c.items }
        if let p: ArticlePage = try? await store.fetch("articles", q) { items = p.items }
        loading = false
    }
}

/// 국가별: 나라마다 최신 기사 몇 건, 누르면 그 나라 전체
struct CountriesScreen: View {
    @Environment(NewsStore.self) private var store
    @State private var groups: [FeedGroup] = []

    var body: some View {
        List {
            OfflineBanner().frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Color.clear)
            ForEach(ordered) { g in
                Section {
                    ForEach(g.items.prefix(5)) { a in
                        NavigationLink(value: Route.article(a.id)) { ArticleRow(item: a, compact: true) }
                            .articleActions(a)
                    }
                    NavigationLink(value: Route.feed(FeedFilter(title: "\(Flag.of(g.key)) \(g.name)", country: g.key))) {
                        Text("\(g.name) 기사 모두 보기").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                    }
                } header: {
                    HStack {
                        Text("\(Flag.of(g.key)) \(g.name)").font(.system(.headline, design: .serif))
                        Spacer()
                        if let c = store.countries.first(where: { $0.code == g.key }) {
                            Text("24시간 \(c.articles24h.grouped)건").font(.caption)
                        }
                    }
                }
            }
            if groups.isEmpty { LoadingRow() }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("국가별")
        .task { await load() }
        .refreshable { await Task { await load() }.value }
        .onChange(of: groups) { _, g in store.requestTitles(g.flatMap(\.items)) }
    }

    private var ordered: [FeedGroup] {
        let by = Dictionary(uniqueKeysWithValues: groups.map { ($0.key, $0) })
        let vis = store.visibleCountries.compactMap { by[$0.code] }
        return vis.isEmpty ? groups : vis
    }

    private func load() async {
        let q: [String: String?] = ["by": "country", "per": "5", "lang": store.lang, "unread": store.ui.hideRead ? "true" : nil]
        if groups.isEmpty, let c: [FeedGroup] = store.cached("feed/grouped", q) { groups = c }
        if let g: [FeedGroup] = try? await store.fetch("feed/grouped", q) { groups = g }
    }
}

/// 언론사별: 나라를 고르면 그 나라 언론사마다 최신 기사
struct SourcesScreen: View {
    @Environment(NewsStore.self) private var store
    @State private var country: String? = nil
    @State private var groups: [FeedGroup] = []
    @State private var loading = false

    private var current: String { country ?? store.visibleCountries.first?.code ?? "KR" }

    var body: some View {
        List {
            Section {
                ChipBar(items: store.visibleCountries.map { (Optional($0.code), "\(Flag.of($0.code)) \($0.nameKo)") },
                        selection: Binding(get: { Optional(current) }, set: { country = $0 }))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            ForEach(groups.filter { !$0.items.isEmpty }) { g in
                Section {
                    ForEach(g.items.prefix(4)) { a in
                        NavigationLink(value: Route.article(a.id)) { ArticleRow(item: a, compact: true) }
                            .articleActions(a)
                    }
                    NavigationLink(value: Route.feed(FeedFilter(title: g.name, source: g.key))) {
                        Text("\(g.name) 기사 모두 보기").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                    }
                } header: {
                    Text(g.name).font(.system(.headline, design: .serif))
                }
            }
            if loading && groups.isEmpty { LoadingRow() }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("언론사별")
        .task(id: current) { await load() }
        .refreshable { await Task { await load() }.value }
        .onChange(of: groups) { _, g in store.requestTitles(g.flatMap(\.items)) }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let q: [String: String?] = ["by": "source", "country": current, "per": "4", "lang": store.lang]
        groups = store.cached("feed/grouped", q) ?? []
        if let g: [FeedGroup] = try? await store.fetch("feed/grouped", q) { groups = g }
    }
}
