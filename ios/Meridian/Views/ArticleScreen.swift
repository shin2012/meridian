import SwiftUI
import Translation
import WebKit

/// 기사 본문. 외국어는 서버 번역(저장본) → 실패하면 아이폰 안에서 번역(Apple 번역, 오프라인 가능).
/// AI 요약은 기기 AI(Apple Intelligence)가 먼저, 안 되면 서버 AI(Gemini). 둘 다 골라 볼 수 있다.
struct ArticleScreen: View {
    @Environment(NewsStore.self) private var store
    @Environment(ReadAloud.self) private var reader
    let id: Int

    @State private var orig: ArticleDetail?
    @State private var serverTr: ArticleDetail?
    @State private var deviceTr: DeviceTranslation?
    @State private var showTr = true
    @State private var trBusy = false
    @State private var trNote: String?
    @State private var trConfig: TranslationSession.Configuration?
    @State private var error: String?
    @State private var summary: SummaryState = .idle
    @State private var showWeb = false

    struct DeviceTranslation: Equatable {
        var title: String
        var summary: String?
        var paragraphs: [String]
        var captions: [String?]
    }

    enum SummaryState: Equatable {
        case idle, busy(String), done(text: String, by: String), failed(String)
    }

    // 지금 보여 줄 내용
    private var shown: (title: String, summary: String?, paragraphs: [String], images: [ArticleImage], translated: Bool)? {
        guard let o = orig else { return nil }
        if showTr, let t = serverTr {
            return (t.item.displayTitle, t.item.summary, t.paragraphs, t.images, true)
        }
        if showTr, let d = deviceTr {
            var imgs = o.images
            for i in imgs.indices where i < d.captions.count { if let c = d.captions[i] { imgs[i].alt = c } }
            return (d.title, d.summary, d.paragraphs, imgs, true)
        }
        return (o.item.displayTitle, o.item.summary, o.paragraphs, o.images, false)
    }

    var body: some View {
        ScrollView {
            if let o = orig, let s = shown {
                content(o, s)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
            } else if let error {
                ContentUnavailableView("기사를 열지 못했어요", systemImage: "wifi.exclamationmark", description: Text(error))
                    .padding(.top, 80)
            } else {
                LoadingRow().padding(.top, 80)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task(id: id) { await load() }
        .translationTask(trConfig) { session in await deviceTranslate(session) }
        .sheet(isPresented: $showWeb) {
            if let s = orig?.item.url, let u = URL(string: s) { OriginalWebView(url: u) }
        }
        .userActivity("kr.b-612.meridian.article", isActive: orig != nil) { act in
            guard let o = orig else { return }
            act.title = o.item.displayTitle
            act.webpageURL = URL(string: o.item.url)       // 맥·아이패드에서 이어서 원문 보기(Handoff)
            act.isEligibleForHandoff = true
        }
    }

    // MARK: 본문

    @ViewBuilder
    private func content(_ o: ArticleDetail, _ s: (title: String, summary: String?, paragraphs: [String], images: [ArticleImage], translated: Bool)) -> some View {
        let ui = store.ui
        VStack(alignment: .leading, spacing: 16) {
            if let hero = heroImage(o) {
                ImageBox(url: hero, height: 240, radius: 20)
            }
            HStack(spacing: 6) {
                Text(Flag.of(o.item.country))
                Text(o.item.source.name).fontWeight(.semibold)
                Text("·")
                Text((o.item.publishedAt ?? o.item.sortAt).formatted(.dateTime.locale(Locale(identifier: "ko_KR")).month().day().hour().minute()))
                if s.translated { BadgeView(text: deviceTr != nil && serverTr == nil ? "기기 번역" : "자동 번역", tone: .dim) }
                if let b = o.item.badge { BadgeView(text: b.text, tone: b.tone) }
            }
            .font(.footnote).foregroundStyle(.secondary)

            Text(s.title).font(.system(.title, design: .serif).weight(.bold)).textSelection(.enabled)
            if let author = o.author, !author.isEmpty {
                Text(author).font(.footnote).foregroundStyle(.secondary)
            }
            if trBusy {
                Label("번역하는 중…", systemImage: "translate").font(.footnote).foregroundStyle(.secondary)
            } else if let n = trNote {
                Label(n, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
            }

            summaryCard(o, s)

            let paras = s.paragraphs
            if paras.isEmpty {
                if let sm = s.summary { Text(sm).font(ui.bodyFont).lineSpacing(ui.lineSpacing) }
                VStack(alignment: .leading, spacing: 8) {
                    Text(o.item.bodyStatus == nil ? "본문을 수집하는 중입니다." : "이 언론사는 본문을 가져올 수 없어 요약만 보여드립니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("원문 보기", systemImage: "safari") { showWeb = true }.buttonStyle(.glass)
                }
            } else {
                let placed = place(s.images, count: paras.count, skipHero: heroImage(o) != nil)
                ForEach(Array(paras.enumerated()), id: \.offset) { i, p in
                    Text(p).font(ui.bodyFont).lineSpacing(ui.lineSpacing).textSelection(.enabled)
                    ForEach(placed[i] ?? [], id: \.src) { im in
                        figure(im)
                    }
                }
            }

            Divider().padding(.top, 8)
            HStack {
                Button("원문 보기", systemImage: "safari") { showWeb = true }
                Spacer()
                if let u = URL(string: o.item.url) {
                    ShareLink(item: u, subject: Text(s.title)) { Label("공유", systemImage: "square.and.arrow.up") }
                }
            }
            .buttonStyle(.glass)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func figure(_ im: ArticleImage) -> some View {
        if let u = URL(string: im.src) {
            VStack(alignment: .leading, spacing: 6) {
                ImageBox(url: u, height: 220)
                if let alt = im.alt, !alt.isEmpty { Text(alt).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    /// 대표 이미지는 본문 앞부분(15% 안)에 사진이 없을 때만(같은 사진 중복 방지 — 웹과 같은 규칙)
    private func heroImage(_ o: ArticleDetail) -> URL? {
        guard let s = o.item.imageUrl, let u = URL(string: s) else { return nil }
        if o.images.contains(where: { $0.at < 0.15 }) { return nil }
        return u
    }

    private func place(_ images: [ArticleImage], count: Int, skipHero: Bool) -> [Int: [ArticleImage]] {
        var out: [Int: [ArticleImage]] = [:]
        for im in images {
            let i = min(count - 1, max(0, Int((im.at * Double(count)).rounded(.down))))
            out[i, default: []].append(im)
        }
        return out
    }

    // MARK: AI 요약

    @ViewBuilder
    private func summaryCard(_ o: ArticleDetail, _ s: (title: String, summary: String?, paragraphs: [String], images: [ArticleImage], translated: Bool)) -> some View {
        switch summary {
        case .idle:
            HStack {
                Button { summarize(prefer: DeviceAI.isAvailable ? .device : .server) } label: {
                    Label("AI 세 줄 요약", systemImage: DeviceAI.isAvailable ? "apple.intelligence" : "sparkles")
                }
                .buttonStyle(.glassProminent)
                Spacer()
            }
        case .busy(let who):
            Label("\(who)가 요약하는 중…", systemImage: "sparkles")
                .font(.callout).foregroundStyle(.secondary)
                .symbolEffect(.pulse)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
        case .done(let text, let by):
            VStack(alignment: .leading, spacing: 8) {
                Label(by, systemImage: by.hasPrefix("기기") ? "apple.intelligence" : "sparkles")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                Text(text).font(.callout).textSelection(.enabled)
                HStack {
                    if by.hasPrefix("기기") {
                        Button("서버 AI로 다시") { summarize(prefer: .server) }
                    } else if DeviceAI.isAvailable {
                        Button("기기 AI로 다시") { summarize(prefer: .device) }
                    }
                    Spacer()
                    Button("들려주기", systemImage: "speaker.wave.2") {
                        reader.play(.init(title: "요약 · \(s.title)", subtitle: o.item.source.name, chunks: [text], language: "ko", articleID: o.item.id))
                    }
                }
                .font(.caption)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.accentColor.opacity(0.12)), in: .rect(cornerRadius: 18))
        case .failed(let msg):
            HStack {
                Label(msg, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("다시") { summary = .idle }
            }
        }
    }

    private enum Engine { case device, server }

    private func summarize(prefer: Engine) {
        guard let o = orig, let s = shown else { return }
        Task {
            if prefer == .device && DeviceAI.isAvailable {
                summary = .busy("기기 AI")
                do {
                    let body = s.paragraphs.isEmpty ? (s.summary ?? "") : s.paragraphs.joined(separator: "\n")
                    let text = try await DeviceAI.summarize(title: s.title, body: body, source: o.item.source.name)
                    summary = .done(text: text, by: "기기 AI 요약 · 인터넷 없이")
                    return
                } catch {
                    // 기기 AI가 거절·실패하면 서버로
                }
            }
            summary = .busy("서버 AI")
            do {
                let r = try await store.serverSummary(o.item.id)
                summary = .done(text: r.summary, by: "서버 AI 요약 · \(r.model ?? "Gemini")")
            } catch {
                summary = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: 받기·번역

    private func load() async {
        let key = DiskCache.key("articles/\(id)", [:])
        if orig == nil { orig = DiskCache.decode(key) ?? store.cachedDetail(id) }
        do {
            let d: ArticleDetail = try await store.fetch("articles/\(id)")
            orig = d
            error = nil
        } catch {
            if orig == nil, !APIError.isCancel(error) { self.error = error.localizedDescription }
        }
        guard let o = orig else { return }
        store.setRead(o.item, true)
        Spotlight.index(o.item)
        if o.item.isForeign && store.ui.translate && serverTr == nil && deviceTr == nil {
            await translate()
        }
    }

    private func translate() async {
        guard let o = orig else { return }
        showTr = true
        trBusy = true
        trNote = nil
        if store.trEngine == .device {
            deviceTranslateStart(o)
            return
        }
        if let cached = store.cachedDetail(id), cached.item.translated {
            serverTr = cached
            trBusy = false
            return
        }
        do {
            serverTr = try await store.serverTranslate(id)
            trBusy = false
        } catch {
            // 서버 번역이 막혔거나(429) 오프라인 → 아이폰 안에서 번역
            trNote = APIError.isOffline(error) ? "오프라인이라 아이폰에서 번역합니다." : "서버 번역이 바빠 아이폰에서 번역합니다."
            let src = o.item.language.map { Locale.Language(identifier: $0) }
            if trConfig == nil {
                trConfig = TranslationSession.Configuration(source: src, target: Locale.Language(identifier: "ko"))
            } else {
                trConfig?.invalidate()
            }
        }
    }

    private func deviceTranslateStart(_ o: ArticleDetail) {
        serverTr = nil
        showTr = true
        trBusy = true
        let src = o.item.language.map { Locale.Language(identifier: $0) }
        if trConfig == nil {
            trConfig = TranslationSession.Configuration(source: src, target: Locale.Language(identifier: "ko"))
        } else { trConfig?.invalidate() }
    }

    private func serverTranslateNow() async {
        deviceTr = nil
        showTr = true
        trBusy = true
        trNote = nil
        do {
            serverTr = try await store.serverTranslate(id)
        } catch {
            trNote = "서버 번역에 실패했습니다. 잠시 뒤 다시 해 주세요."
        }
        trBusy = false
    }

    private func deviceTranslate(_ session: TranslationSession) async {
        guard let o = orig else { return }
        var texts: [String] = [o.item.displayTitle, o.item.summary ?? ""]
        texts += o.paragraphs
        texts += o.images.map { $0.alt ?? "" }
        let reqs = texts.enumerated().compactMap { i, t in
            t.isEmpty ? nil : TranslationSession.Request(sourceText: t, clientIdentifier: String(i))
        }
        do {
            let res = try await session.translations(from: reqs)
            var out = texts
            for r in res { if let i = r.clientIdentifier.flatMap(Int.init) { out[i] = r.targetText } }
            let np = o.paragraphs.count
            deviceTr = DeviceTranslation(
                title: out[0], summary: out[1].isEmpty ? nil : out[1],
                paragraphs: Array(out[2..<(2 + np)]),
                captions: out[(2 + np)...].map { $0.isEmpty ? nil : $0 })
            trNote = nil
            store.deviceLanguageReady(o.item.language)
        } catch {
            trNote = "번역하지 못했습니다. 원문을 보여 드려요."
            showTr = false
        }
        trBusy = false
    }

    // MARK: 도구 막대

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let o = orig {
            let a = store.apply(o.item)
            ToolbarItem(placement: .topBarTrailing) {
                Button(store.isBookmarked(a) ? "북마크 해제" : "북마크",
                       systemImage: store.isBookmarked(a) ? "bookmark.fill" : "bookmark") {
                    store.setBookmark(a, !store.isBookmarked(a))
                }
                .sensoryFeedback(.selection, trigger: store.isBookmarked(a))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("읽어 주기", systemImage: reader.track?.articleID == o.item.id ? "speaker.wave.2.fill" : "speaker.wave.2") {
                    if reader.track?.articleID == o.item.id { reader.toggle() } else {
                        var d = serverTr ?? o
                        if showTr, serverTr == nil, let t = deviceTr {
                            d.item.title = t.title
                            d.body = t.paragraphs.joined(separator: "\n")
                            d.item.translated = true
                        }
                        if !showTr { d = o }
                        reader.playArticle(d)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if o.item.isForeign {
                        if showTr && (serverTr != nil || deviceTr != nil) {
                            Button("원문 보기", systemImage: "character.book.closed") { showTr = false }
                        } else {
                            Button("번역 보기", systemImage: "translate") {
                                if serverTr != nil || deviceTr != nil { showTr = true } else { Task { await translate() } }
                            }
                        }
                        if store.trEngine == .device {
                            Button("서버(Claude)로 번역", systemImage: "server.rack") { Task { await serverTranslateNow() } }
                        } else {
                            Button("아이폰에서 번역", systemImage: "iphone") { deviceTranslateStart(o) }
                        }
                    }
                    Button("원문 보기(웹)", systemImage: "safari") { showWeb = true }
                    if let u = URL(string: o.item.url) {
                        ShareLink(item: u) { Label("공유", systemImage: "square.and.arrow.up") }
                    }
                    Button(store.isRead(a) ? "안 읽음으로" : "읽음으로", systemImage: "checkmark.circle") {
                        store.setRead(a, !store.isRead(a))
                    }
                } label: {
                    Label("더 보기", systemImage: "ellipsis")
                }
            }
        }
    }
}

/// 원문 웹페이지(iOS 26 SwiftUI WebView)
struct OriginalWebView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var page = WebPage()

    var body: some View {
        NavigationStack {
            WebView(page)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(page.title.isEmpty ? (url.host() ?? "원문") : page.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("닫기", systemImage: "xmark") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Link(destination: url) { Image(systemName: "safari") } }
                }
                .overlay(alignment: .top) {
                    if page.isLoading {
                        ProgressView(value: page.estimatedProgress).progressViewStyle(.linear)
                    }
                }
                .onAppear { page.load(URLRequest(url: url)) }
        }
    }
}
