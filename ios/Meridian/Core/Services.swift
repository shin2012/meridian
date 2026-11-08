import BackgroundTasks
import CoreSpotlight
import Foundation
import Observation
import UIKit
import UserNotifications

/// 푸시 알림: 권한 → APNs 등록 → 서버에 기기 토큰과 알림 설정을 보낸다.
@MainActor @Observable
final class Push {
    static let shared = Push()

    var status: UNAuthorizationStatus = .notDetermined
    var prefs: DevicePrefs = {
        if let d = UserDefaults.standard.data(forKey: "pushPrefs"), let p = try? JSONDecoder().decode(DevicePrefs.self, from: d) {
            return p
        }
        return DevicePrefs()
    }()
    var token: String? = UserDefaults.standard.string(forKey: "apnsToken")
    var lastError: String?
    var registered = false

    /// 실행·활성화 때마다: 권한이 있으면 등록(토큰이 바뀌었을 수 있음)
    func sync() {
        Task {
            let s = await UNUserNotificationCenter.current().notificationSettings()
            status = s.authorizationStatus
            if status == .authorized || status == .provisional {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func requestPermission() async {
        do {
            let ok = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            status = ok ? .authorized : .denied
            if ok { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func didRegister(_ hex: String) {
        token = hex
        UserDefaults.standard.set(hex, forKey: "apnsToken")
        Task { await upload() }
    }

    func update(_ p: DevicePrefs) {
        prefs = p
        UserDefaults.standard.set(try? JSONEncoder().encode(p), forKey: "pushPrefs")
        Task { await upload() }
    }

    func upload() async {
        guard let token, let api = NewsStore.shared.api else { return }
        struct Body: Encodable { let prefs: DevicePrefs }
        do {
            _ = try await api.send("PUT", "devices/\(token)", body: Body(prefs: prefs))
            registered = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// 백그라운드 새로고침: iOS가 허락하는 때에 주요 뉴스·위젯·표본 기사 본문을 받는다.
enum BackgroundRefresh {
    static let id = "kr.b-612.meridian.refresh"

    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: id)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 45 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    static func run() async {
        await MainActor.run { schedule() }
        let store = await NewsStore.shared
        _ = await store.refreshDigest()
        await store.flushOutbox()
    }
}

/// 기기 검색(Spotlight): 북마크한 기사와 열어 본 기사를 아이폰 검색에서 찾게 한다.
enum Spotlight {
    static let activityType = CSSearchableItemActionType
    static let domain = "kr.b-612.meridian.article"

    static func index(_ a: ArticleItem, bookmarked: Bool? = nil) {
        let attr = CSSearchableItemAttributeSet(contentType: .text)
        attr.title = a.displayTitle
        attr.contentDescription = [a.source.name, a.summary].compactMap { $0 }.joined(separator: " · ")
        attr.keywords = [a.source.name, Flag.of(a.country), a.topic].compactMap { $0 }
        if let s = a.imageUrl, let u = URL(string: s) { attr.thumbnailURL = u }
        let item = CSSearchableItem(uniqueIdentifier: "article-\(a.id)", domainIdentifier: domain, attributeSet: attr)
        item.expirationDate = (bookmarked ?? a.bookmarked) ? .distantFuture : Date(timeIntervalSinceNow: 14 * 86400)
        CSSearchableIndex.default().indexSearchableItems([item])
    }

    static func articleID(from act: NSUserActivity) -> Int? {
        guard let s = act.userInfo?[CSSearchableItemActivityIdentifier] as? String, s.hasPrefix("article-") else { return nil }
        return Int(s.dropFirst(8))
    }

    static func clear() { CSSearchableIndex.default().deleteAllSearchableItems() }
}
