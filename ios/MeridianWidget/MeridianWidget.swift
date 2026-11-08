import AppIntents
import SwiftUI
import WidgetKit

@main
struct MeridianWidgets: WidgetBundle {
    var body: some Widget {
        TopNewsWidget()
        TopNewsControl()
    }
}

// MARK: - 주요 뉴스 위젯

struct TopNewsEntry: TimelineEntry {
    let date: Date
    let news: TopNews
    let stale: Bool
}

struct TopNewsProvider: TimelineProvider {
    func placeholder(in context: Context) -> TopNewsEntry {
        TopNewsEntry(date: .now, news: .placeholder, stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (TopNewsEntry) -> Void) {
        completion(TopNewsEntry(date: .now, news: TopNews.load() ?? .placeholder, stale: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TopNewsEntry>) -> Void) {
        Task {
            var news = TopNews.load()
            var stale = true
            if let a = Account.load(), let fresh = try? await TopNewsFetcher.fetch(a) {
                fresh.save()
                news = fresh
                stale = false
            }
            let entry = TopNewsEntry(date: .now, news: news ?? .placeholder, stale: stale && news != nil)
            // 분석은 매시 5분 → 다음 정각 10분쯤 다시
            let next = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 10), matchingPolicy: .nextTime)
                ?? .now.addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct TopNewsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TopNews", provider: TopNewsProvider()) { entry in
            TopNewsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.06, green: 0.09, blue: 0.20), Color(red: 0.10, green: 0.16, blue: 0.32)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("주요 뉴스")
        .description("여러 나라 언론이 함께 다룬 사건 순위. 1시간마다 바뀝니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryRectangular, .accessoryInline])
    }
}

struct TopNewsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode
    let entry: TopNewsEntry

    private var items: [TopNews.Item] { entry.news.items }
    private let gold = Color(red: 0.96, green: 0.78, blue: 0.36)

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(items.first.map { "🌐 \($0.title)" } ?? "자오선")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("주요 뉴스 1위").font(.caption2.weight(.semibold)).widgetAccentable()
                Text(items.first?.title ?? "불러오는 중").font(.headline).lineLimit(2)
            }
            .widgetURL(url(items.first))
        case .systemSmall:
            small
        default:
            list(count: family == .systemMedium ? 3 : 5, showSummary: family == .systemLarge || family == .systemExtraLarge)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            if let e = items.first {
                Text("1").font(.system(size: 30, weight: .black, design: .serif)).foregroundStyle(gold).widgetAccentable()
                Text(e.title).font(.system(.subheadline, design: .serif).weight(.bold)).foregroundStyle(.white).lineLimit(4)
                Text(Flag.row(e.countries, max: 5)).font(.caption2)
            }
        }
        .widgetURL(url(items.first))
    }

    private func list(count: Int, showSummary: Bool) -> some View {
        VStack(alignment: .leading, spacing: showSummary ? 10 : 7) {
            header
            ForEach(items.prefix(count)) { e in
                Link(destination: url(e)) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(e.rank)").font(.system(.title3, design: .serif).weight(.black)).foregroundStyle(gold)
                            .frame(width: 18).widgetAccentable()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).font(.system(.subheadline, design: .serif).weight(.semibold))
                                .foregroundStyle(.white).lineLimit(showSummary ? 2 : 1)
                            if showSummary, let s = e.summary {
                                Text(s).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                            } else {
                                Text("\(Flag.row(e.countries, max: 5)) · 기사 \(e.articles)건").font(.caption2).foregroundStyle(.white.opacity(0.65))
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe.asia.australia.fill").foregroundStyle(gold).widgetAccentable()
            Text("자오선").font(.caption.weight(.bold)).foregroundStyle(.white)
            Spacer()
            Text(entry.news.analyzedAt, style: .relative).font(.caption2).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.trailing)
        }
    }

    private func url(_ e: TopNews.Item?) -> URL {
        guard let e else { return URL(string: "meridian://digest")! }
        return URL(string: "meridian://event/\(e.id)")!
    }
}

// MARK: - 제어 센터·잠금 화면 버튼

struct TopNewsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "kr.b-612.meridian.control.top") {
            ControlWidgetButton(action: OpenTopNewsIntent()) {
                Label("주요 뉴스", systemImage: "globe.asia.australia.fill")
            }
        }
        .displayName("자오선 주요 뉴스")
        .description("자오선을 열고 주요 뉴스를 봅니다.")
    }
}
