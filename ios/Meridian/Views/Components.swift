import SwiftUI
import ImageIO

// MARK: - 글자 크기(웹 설정 s/m/l)

extension UiSettings {
    var bodyFont: Font {
        switch fontSize {
        case "s": .system(.callout, design: .serif)
        case "l": .system(.title3, design: .serif)
        default: .system(.body, design: .serif)
        }
    }
    var lineSpacing: CGFloat { fontSize == "l" ? 9 : fontSize == "s" ? 5 : 7 }
}

// MARK: - 기사 한 줄

struct ArticleRow: View {
    @Environment(NewsStore.self) private var store
    let item: ArticleItem
    var compact = false

    var body: some View {
        let a = store.apply(item)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(Flag.of(a.country))
                    Text(a.source.name).fontWeight(.semibold)
                    Text("·")
                    Text(MeridianDate.ago(a.sortAt))
                    if let b = a.badge { BadgeView(text: b.text, tone: b.tone) }
                    if a.translated && a.isForeign { BadgeView(text: "번역", tone: .dim) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Text(a.displayTitle)
                    .font(.system(compact ? .subheadline : .headline, design: .serif))
                    .foregroundStyle(store.isRead(a) ? .secondary : .primary)
                    .lineLimit(compact ? 2 : 3)

                if !compact, let s = a.summary, !s.isEmpty {
                    Text(s).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if !compact, let s = a.imageUrl, let u = URL(string: s) {
                RemoteImage(url: u)
                    .frame(width: 84, height: 84)
                    .clipShape(.rect(cornerRadius: 12))
            }
            if store.isBookmarked(a) {
                Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

struct BadgeView: View {
    let text: String
    let tone: Badge.Tone
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }
    private var color: Color {
        switch tone { case .pay: .orange; case .dim: .secondary; case .wait: .blue }
    }
}

/// 정해진 높이의 사진 칸. 사진 원래 크기가 레이아웃 폭을 밀어내지 않도록 빈 칸 위에 겹쳐 그린다.
struct ImageBox: View {
    let url: URL
    var height: CGFloat
    var radius: CGFloat = 14
    var body: some View {
        Color.secondary.opacity(0.06)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay { RemoteImage(url: url) }
            .clipShape(.rect(cornerRadius: radius))
    }
}

/// 언론사 사진: 원본 주소 그대로. 못 불러오면 자리를 비운다.
/// 발열·메모리 방지: AsyncImage는 원본(수천 픽셀) 그대로 풀고 스크롤할 때마다 다시 받아서,
/// 표시 크기에 맞게 줄여(ImageIO 썸네일) 메모리 캐시에 두고 다시 쓴다.
struct RemoteImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.secondary.opacity(0.08)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                        .transition(.opacity)
                }
            }
            .task(id: url) {
                let side = max(geo.size.width, geo.size.height)
                if let img = await ImagePipeline.shared.image(url, maxPoints: side > 0 ? side : 400) {
                    withAnimation(.easeOut(duration: 0.2)) { image = img }
                }
            }
        }
    }
}

/// 줄인 사진 메모리 캐시 + 디스크(URLCache) 캐시. 같은 사진을 동시에 여러 번 받지 않는다.
actor ImagePipeline {
    static let shared = ImagePipeline()
    private let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 48 << 20          // 약 48MB(줄인 비트맵 기준)
        return c
    }()
    private var running: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 200 << 20)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.httpMaximumConnectionsPerHost = 4
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    func image(_ url: URL, maxPoints: CGFloat) async -> UIImage? {
        let px = Int(min(maxPoints, 1200) * 3)          // 화면 배율 3 기준, 상한 3600px
        let key = "\(url.absoluteString)#\(px)" as NSString
        if let hit = memory.object(forKey: key) { return hit }
        if let t = running[key as String] { return await t.value }
        let t = Task<UIImage?, Never> { [session] in
            var req = URLRequest(url: url)
            req.setValue(nil, forHTTPHeaderField: "Referer")
            guard let (data, _) = try? await session.data(for: req) else { return nil }
            return Self.downsample(data, maxPixel: px)
        }
        running[key as String] = t
        let img = await t.value
        running[key as String] = nil
        if let img {
            let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
            memory.setObject(img, forKey: key, cost: cost)
        }
        return img
    }

    nonisolated static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - 기사 목록 공통 동작(밀기·길게 누르기)

struct ArticleActions: ViewModifier {
    @Environment(NewsStore.self) private var store
    @Environment(ReadAloud.self) private var reader
    let item: ArticleItem

    func body(content: Content) -> some View {
        let a = store.apply(item)
        content
            .swipeActions(edge: .trailing) {
                Button(store.isBookmarked(a) ? "북마크 해제" : "북마크", systemImage: store.isBookmarked(a) ? "bookmark.slash" : "bookmark") {
                    store.setBookmark(a, !store.isBookmarked(a))
                }
                .tint(.orange)
            }
            .swipeActions(edge: .leading) {
                Button(store.isRead(a) ? "안 읽음" : "읽음", systemImage: store.isRead(a) ? "circle" : "checkmark.circle") {
                    store.setRead(a, !store.isRead(a))
                }
                .tint(.blue)
            }
            .contextMenu {
                Button(store.isBookmarked(a) ? "북마크 해제" : "북마크", systemImage: "bookmark") {
                    store.setBookmark(a, !store.isBookmarked(a))
                }
                if let u = URL(string: a.url) {
                    ShareLink(item: u, subject: Text(a.displayTitle)) { Label("공유", systemImage: "square.and.arrow.up") }
                    Link(destination: u) { Label("원문 열기", systemImage: "safari") }
                }
                Button("읽어 주기", systemImage: "speaker.wave.2") {
                    Task {
                        var d = store.cachedDetail(a.id)
                        if d == nil { d = try? await store.detail(a.id) }
                        if let d { reader.playArticle(d) }
                    }
                }
            } preview: {
                ArticlePreview(item: a)
            }
    }
}

extension View {
    func articleActions(_ a: ArticleItem) -> some View { modifier(ArticleActions(item: a)) }
}

struct ArticlePreview: View {
    let item: ArticleItem
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let s = item.imageUrl, let u = URL(string: s) {
                ImageBox(url: u, height: 180, radius: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Flag.of(item.country)) \(item.source.name) · \(MeridianDate.ago(item.sortAt))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(item.displayTitle).font(.system(.title3, design: .serif).weight(.semibold))
                if let s = item.summary { Text(s).font(.subheadline).foregroundStyle(.secondary).lineLimit(6) }
            }
            .padding()
        }
        .frame(width: 360)
    }
}

// MARK: - 칩(국가 고르기 등)

struct ChipBar<T: Hashable>: View {
    let items: [(T?, String)]
    @Binding var selection: T?

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                        let on = it.0 == selection
                        Button {
                            withAnimation(.snappy) { selection = it.0 }
                        } label: {
                            Text(it.1)
                                .font(.subheadline.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(on ? .regular.tint(.accentColor.opacity(0.35)).interactive() : .regular.interactive(), in: .capsule)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - 상태 표시

struct OfflineBanner: View {
    @Environment(NewsStore.self) private var store
    var body: some View {
        if store.offline {
            Label(store.pendingCount > 0 ? "오프라인 · 보내지 못한 변경 \(store.pendingCount)건" : "오프라인 · 저장된 내용을 보여 드려요",
                  systemImage: "wifi.slash")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .capsule)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct LoadingRow: View {
    var text = "불러오는 중…"
    var body: some View {
        HStack { Spacer(); ProgressView(); Text(text).foregroundStyle(.secondary); Spacer() }
            .padding(.vertical, 24)
            .listRowSeparator(.hidden)
    }
}

/// 카드 숫자(분석 통계)
struct StatTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit().contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

extension Double {
    var percent: String { (self * 100).formatted(.number.precision(.fractionLength(0))) + "%" }
}

extension Int {
    var grouped: String { formatted(.number.locale(Locale(identifier: "ko_KR"))) }
}
