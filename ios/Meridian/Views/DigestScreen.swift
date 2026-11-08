import SwiftUI

/// 주요 뉴스: 최근 24시간 여러 나라 언론이 함께 다룬 사건 순위(1시간마다 분석)
struct DigestScreen: View {
    @Environment(NewsStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ReadAloud.self) private var reader
    @State private var briefingBusy = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                OfflineBanner().frame(maxWidth: .infinity)
                if let d = store.digest {
                    header(d)
                    sectionTitle("전 세계 주요 뉴스 5")
                    ForEach(d.top) { e in
                        NavigationLink(value: Route.event(id: e.id, title: e.displayTitle)) {
                            TopEventCard(event: e)
                        }
                        .buttonStyle(.plain)
                    }
                    if !d.rest.isEmpty {
                        sectionTitle("그 밖의 공통 사건")
                        VStack(spacing: 0) {
                            ForEach(d.rest) { e in
                                NavigationLink(value: Route.event(id: e.id, title: e.displayTitle)) {
                                    MinorEventRow(event: e)
                                }
                                .buttonStyle(.plain)
                                if e.id != d.rest.last?.id { Divider().padding(.leading, 44) }
                            }
                        }
                        .background(.background.secondary, in: .rect(cornerRadius: 20))
                    }
                } else if let err = store.lastError {
                    ContentUnavailableView("주요 뉴스를 받지 못했어요", systemImage: "exclamationmark.triangle", description: Text(err))
                } else {
                    LoadingRow()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .refreshable { await Task { await store.refreshAll() }.value }
        .navigationTitle("자오선")
        .navigationSubtitle(store.digest.map { "최근 24시간 · \(MeridianDate.ago($0.createdAt)) 분석" } ?? "")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("주요 뉴스 브리핑 듣기", systemImage: "headphones") {
                        if let d = store.digest { reader.playBriefing(d) }
                    }
                    if DeviceAI.isAvailable {
                        Button("기기 AI가 쓴 브리핑 듣기", systemImage: "apple.intelligence") { aiBriefing() }
                    }
                } label: {
                    Label("듣기", systemImage: briefingBusy ? "ellipsis" : "headphones")
                        .symbolEffect(.pulse, isActive: briefingBusy)
                }
                .disabled(store.digest == nil)
            }
        }
    }

    private func header(_ d: Digest) -> some View {
        let s = d.stats
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatTile(value: (s.articles ?? 0).grouped, label: "분석한 기사")
            StatTile(value: (s.shareMultiSource ?? 0).percent, label: "여러 언론사가 함께 다룬 기사")
            StatTile(value: (s.shareMultiCountry ?? 0).percent, label: "여러 나라가 함께 다룬 기사")
            StatTile(value: (s.groupsMultiCountry ?? 0).grouped, label: "여러 나라 공통 사건")
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(.title2, design: .serif).weight(.bold)).padding(.top, 6)
    }

    private func aiBriefing() {
        guard let d = store.digest else { return }
        briefingBusy = true
        Task {
            defer { briefingBusy = false }
            if let script = try? await DeviceAI.briefing(d) {
                let chunks = script.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                reader.play(.init(title: "AI 브리핑", subtitle: "자오선 · 기기 AI", chunks: chunks, language: "ko", articleID: nil))
            } else {
                reader.playBriefing(d)
            }
        }
    }
}

struct TopEventCard: View {
    let event: NewsEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(event.rank)")
                    .font(.system(size: 34, weight: .black, design: .serif))
                    .foregroundStyle(.tint)
                Text(event.displayTitle)
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .multilineTextAlignment(.leading)
            }
            if let s = event.summary {
                Text(s).font(.callout).foregroundStyle(.secondary).lineLimit(4)
            }
            HStack(spacing: 8) {
                Text(Flag.row(event.countries, max: 8))
                Spacer()
                Text("\(event.countries.count)개국 · 언론사 \(event.sources)곳 · 기사 \(event.articles)건")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !event.samples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(event.samples) { a in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Flag.of(a.country))
                            Text(a.displayTitle).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(a.source.name).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .font(.footnote)
                    }
                }
                .padding(10)
                .background(.background.tertiary, in: .rect(cornerRadius: 12))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
    }
}

struct MinorEventRow: View {
    let event: NewsEvent
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(event.rank)").font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.displayTitle).font(.system(.subheadline, design: .serif).weight(.semibold))
                Text("\(Flag.row(event.countries, max: 5)) · 기사 \(event.articles)건").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(.rect)
    }
}

/// 사건 하나: 나라별 관련 기사 전체 + (기기 AI) 나라별 관점 비교
struct EventScreen: View {
    @Environment(NewsStore.self) private var store
    let id: Int
    let title: String
    @State private var items: [ArticleItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var perspective: String?
    @State private var aiBusy = false

    private var event: NewsEvent? { store.digest?.events.first { $0.id == id } }

    var body: some View {
        List {
            if let e = event {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(e.displayTitle).font(.system(.title2, design: .serif).weight(.bold))
                        if let s = e.summary { Text(s).font(.callout) }
                        Text("\(Flag.row(e.countries, max: 10)) · 언론사 \(e.sources)곳 · 기사 \(e.articles)건")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    if DeviceAI.isAvailable {
                        if let p = perspective {
                            Label { Text(p).font(.callout) } icon: { Image(systemName: "apple.intelligence") }
                        } else {
                            Button {
                                aiBusy = true
                                Task {
                                    var ev = e
                                    if ev.samples.count < 4 { ev.samples = Array(items.prefix(6)) }
                                    perspective = (try? await DeviceAI.explain(ev)) ?? "기기 AI가 답하지 못했어요."
                                    aiBusy = false
                                }
                            } label: {
                                Label(aiBusy ? "정리하는 중…" : "나라별 보도 관점 비교(기기 AI)", systemImage: "apple.intelligence")
                            }
                            .disabled(aiBusy)
                        }
                    }
                }
            }
            let byCountry = Dictionary(grouping: items, by: \.country)
            ForEach(byCountry.keys.sorted { (byCountry[$0]?.count ?? 0) > (byCountry[$1]?.count ?? 0) }, id: \.self) { c in
                Section("\(Flag.of(c)) \(store.countryName(c)) · \(byCountry[c]?.count ?? 0)건") {
                    ForEach(byCountry[c] ?? []) { a in
                        NavigationLink(value: Route.article(a.id)) { ArticleRow(item: a, compact: true) }
                            .articleActions(a)
                    }
                }
            }
            if loading && items.isEmpty { LoadingRow() }
            if let error, items.isEmpty { Text(error).foregroundStyle(.secondary) }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await Task { await load() }.value }
        .onChange(of: items) { _, v in store.requestTitles(v) }
    }

    private func load() async {
        let path = "clusters/\(id)/articles"
        let q: [String: String?] = ["lang": store.lang]
        if items.isEmpty, let c: ArticlePage = store.cached(path, q) { items = c.items }
        do {
            let p: ArticlePage = try await store.fetch(path, q)
            items = p.items
            error = nil
        } catch {
            if !APIError.isCancel(error) { self.error = error.localizedDescription }
        }
        loading = false
    }
}
