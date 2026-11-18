import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import UserNotifications

@main
struct MeridianApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #else
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
    #endif
    @State private var store = NewsStore.shared
    @State private var router = Router.shared
    @State private var reader = ReadAloud.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(reader)
                .onOpenURL { router.open($0) }
                .onContinueUserActivity(Spotlight.activityType) { act in
                    if let id = Spotlight.articleID(from: act) { router.push(.article(id)) }
                }
                .onChange(of: phase) { _, p in
                    guard p == .active else { return }
                    if let url = PendingLink.take() { router.open(url) }
                    Task { await store.refreshAll() }
                    BackgroundRefresh.schedule()
                }
        }
        #if os(iOS)
        .backgroundTask(.appRefresh(BackgroundRefresh.id)) {
            await BackgroundRefresh.run()
        }
        #else
        .defaultSize(width: 1180, height: 820)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("설정…") { Router.shared.showSettings = true }.keyboardShortcut(",")
            }
            CommandGroup(after: .toolbar) {
                Button("새로고침") { Task { await NewsStore.shared.refreshAll() } }.keyboardShortcut("r")
            }
        }
        #endif
    }
}

#if os(iOS)

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in Push.shared.sync() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in Push.shared.didRegister(hex) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in Push.shared.lastError = error.localizedDescription }
    }

    /// 조용한 푸시(새 분석) → 주요 뉴스와 위젯을 미리 받는다
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async
        -> UIBackgroundFetchResult {
        let changed = await NewsStore.shared.refreshDigest()
        return changed ? .newData : .noData
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let s = info["url"] as? String, let url = URL(string: s) {
            await MainActor.run { Router.shared.open(url) }
        }
    }
}
#else
final class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in Push.shared.sync() }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in Push.shared.didRegister(hex) }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in Push.shared.lastError = error.localizedDescription }
    }

    /// 조용한 푸시(새 분석) → 주요 뉴스와 위젯을 미리 받는다
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task { _ = await NewsStore.shared.refreshDigest() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let s = info["url"] as? String, let url = URL(string: s) {
            await MainActor.run { Router.shared.open(url) }
        }
    }
}
#endif
