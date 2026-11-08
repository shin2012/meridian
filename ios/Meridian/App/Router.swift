import Foundation
import Observation

enum AppTab: String, Hashable, CaseIterable {
    case digest, topics, countries, sources, bookmarks, search

    /// 웹 설정의 defaultView 값과 맞춘다
    init(view: String) {
        switch view {
        case "timeline": self = .topics
        case "country": self = .countries
        case "source": self = .sources
        case "bookmark": self = .bookmarks
        default: self = .digest
        }
    }
}

/// 화면 이동 대상(모든 탭의 NavigationStack이 같이 쓴다)
enum Route: Hashable {
    case article(Int)
    case event(id: Int, title: String)
    case feed(FeedFilter)
}

struct FeedFilter: Hashable {
    var title: String
    var country: String?
    var source: String?
    var topic: String?
    var query: String?
    var bookmarked = false
}

@MainActor @Observable
final class Router {
    static let shared = Router()

    var tab: AppTab = .digest
    var paths: [AppTab: [Route]] = [:]
    var showSettings = false
    var showSetup = false
    var searchText = ""
    var pendingBriefing = false
    var setupPrefill: (server: String, token: String)?

    func push(_ r: Route, on t: AppTab? = nil) {
        let t = t ?? tab
        paths[t, default: []].append(r)
    }

    /// meridian://digest · event/<id> · article/<id> · briefing · search?q= · setup?server=&token=
    func open(_ url: URL) {
        guard url.scheme == "meridian" else { return }
        let host = url.host() ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ k: String) -> String? { q.first { $0.name == k }?.value }
        switch host {
        case "digest":
            tab = .digest
            paths[.digest] = []
        case "event":
            if let id = parts.first.flatMap(Int.init) {
                tab = .digest
                paths[.digest] = [.event(id: id, title: item("title") ?? "사건")]
            }
        case "article":
            if let id = parts.first.flatMap(Int.init) {
                paths[tab, default: []].append(.article(id))
            }
        case "briefing":
            tab = .digest
            pendingBriefing = true
        case "search":
            tab = .search
            searchText = item("q") ?? ""
        case "setup":
            setupPrefill = (item("server") ?? "", item("token") ?? "")
            showSetup = true
        default:
            break
        }
    }
}
