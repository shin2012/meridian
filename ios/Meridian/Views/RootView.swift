import SwiftUI

struct RootView: View {
    @Environment(NewsStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ReadAloud.self) private var reader
    @Environment(\.horizontalSizeClass) private var hsize

    var body: some View {
        @Bindable var router = router
        tabs
            .modifier(PlayerAccessory(active: reader.active))
            .sheet(isPresented: $router.showSettings) { SettingsScreen() }
            .fullScreenCover(isPresented: Binding(get: { !store.isConfigured || router.showSetup },
                                                  set: { if !$0 { router.showSetup = false } })) {
                SetupView()
            }
            .task {
                #if DEBUG
                await DemoLaunch.apply(store: store, router: router)
                #endif
                await store.refreshAll()
            }
            .onChange(of: router.pendingBriefing) { _, on in
                guard on, let d = store.digest else { return }
                router.pendingBriefing = false
                reader.playBriefing(d)
            }
    }

    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.tab) {
            Tab("주요 뉴스", systemImage: "globe.asia.australia.fill", value: AppTab.digest) {
                TabRoot(tab: .digest) { DigestScreen() }
            }
            Tab("주제별", systemImage: "square.grid.3x2", value: AppTab.topics) {
                TabRoot(tab: .topics) { TopicsScreen() }
            }
            Tab(hsize == .compact ? "국가·언론사" : "국가별", systemImage: "flag", value: AppTab.countries) {
                TabRoot(tab: .countries) {
                    if hsize == .compact { CountryOrSourceScreen() } else { CountriesScreen() }
                }
            }
            // 아이폰 탭 막대는 검색 포함 5칸 — 언론사별은 국가별 화면 안에서 고른다
            if hsize != .compact {
                Tab("언론사별", systemImage: "newspaper", value: AppTab.sources) {
                    TabRoot(tab: .sources) { SourcesScreen() }
                }
            }
            Tab("북마크", systemImage: "bookmark", value: AppTab.bookmarks) {
                TabRoot(tab: .bookmarks) {
                    FeedScreen(filter: FeedFilter(title: "북마크", bookmarked: true))
                }
            }
            Tab(value: AppTab.search, role: .search) {
                TabRoot(tab: .search) { SearchScreen() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: hsize) { _, h in
            if h == .compact && router.tab == .sources { router.tab = .countries; router.sourcesMode = true }
        }
        .onChange(of: router.tab) { _, t in
            if hsize == .compact && t == .sources { router.tab = .countries; router.sourcesMode = true }
        }
    }
}

/// 읽어 주기 중일 때만 탭 막대 위에 작은 재생 막대(iOS 26 하단 보조 영역)
private struct PlayerAccessory: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.tabViewBottomAccessory { NowPlayingBar() }
        } else {
            content
        }
    }
}

/// 탭마다 하나의 NavigationStack. 경로는 Router에 있어 알림·위젯 링크로 바로 들어갈 수 있다.
struct TabRoot<Content: View>: View {
    @Environment(Router.self) private var router
    let tab: AppTab
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack(path: Binding(get: { router.paths[tab] ?? [] }, set: { router.paths[tab] = $0 })) {
            content
                .navigationDestination(for: Route.self) { r in
                    switch r {
                    case .article(let id): ArticleScreen(id: id)
                    case .event(let id, let title): EventScreen(id: id, title: title)
                    case .feed(let f): FeedScreen(filter: f)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("설정", systemImage: "gearshape") { router.showSettings = true }
                    }
                }
        }
    }
}

struct NowPlayingBar: View {
    @Environment(ReadAloud.self) private var reader
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, isActive: reader.speaking && !reader.paused)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(reader.track?.title ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
                ProgressView(value: reader.progress).progressViewStyle(.linear).tint(.accentColor)
            }
            .onTapGesture {
                if let id = reader.track?.articleID { router.push(.article(id)) }
            }
            Button { reader.previous() } label: { Image(systemName: "backward.fill") }
            Button { reader.toggle() } label: {
                Image(systemName: reader.paused || !reader.speaking ? "play.fill" : "pause.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            Button { reader.next() } label: { Image(systemName: "forward.fill") }
            Button { reader.stop() } label: { Image(systemName: "xmark") }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}

#if DEBUG
/// CI 화면 점검용(디버그 빌드만): -demoServer <주소> -demoToken <토큰> -open <meridian://…>
enum DemoLaunch {
    static var active: Bool { UserDefaults.standard.string(forKey: "demoServer") != nil }

    @MainActor static func apply(store: NewsStore, router: Router) async {
        let ud = UserDefaults.standard
        if !store.isConfigured, let s = ud.string(forKey: "demoServer"), let t = ud.string(forKey: "demoToken"),
           let u = Account.normalize(s) {
            try? await store.connect(Account(server: u, token: t))
        }
        if let o = ud.string(forKey: "open"), let url = URL(string: o) {
            try? await Task.sleep(for: .milliseconds(300))
            router.open(url)
        }
    }
}
#endif

/// 아이폰: 국가별·언론사별을 한 탭에서 골라 본다
struct CountryOrSourceScreen: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        let mode = Binding(get: { router.sourcesMode ? 1 : 0 }, set: { router.sourcesMode = $0 == 1 })
        return SwiftUI.Group {
            if mode.wrappedValue == 0 { CountriesScreen() } else { SourcesScreen() }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("보기", selection: mode) {
                    Text("국가별").tag(0)
                    Text("언론사별").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }
}
