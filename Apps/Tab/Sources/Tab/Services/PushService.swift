import Foundation
import UIKit
import UserNotifications
import os

private let pushLog = Logger(subsystem: "com.example.tab", category: "push")

/// Deep-link target carried in a push payload (custom keys sibling to `aps`).
/// Parsed off the main actor in the app delegate, then handed to the UI.
struct PushPayload: Sendable, Equatable, Hashable {
    let tripID: UUID
    let entityType: String?
    let entityID: UUID?

    init?(userInfo: [AnyHashable: Any]) {
        guard let tripRaw = userInfo["trip_id"] as? String,
              let tripID = UUID(uuidString: tripRaw) else { return nil }
        self.tripID = tripID
        self.entityType = userInfo["entity_type"] as? String
        self.entityID = (userInfo["entity_id"] as? String).flatMap(UUID.init)
    }
}

/// Single source for push state. The app delegate feeds it; the UI observes it.
@MainActor
@Observable
final class PushService {
    static let shared = PushService()
    private init() {}

    /// Most recent APNs device token (hex). Observed by the UI to upsert push_devices.
    private(set) var deviceToken: String?
    /// Set when the user taps a notification; the UI consumes it to deep-link, then clears it.
    var lastTap: PushPayload?
    /// Set when a push arrives while the app is foregrounded; the UI consumes
    /// it to refresh the feed the banner is announcing, then clears it.
    var lastForegroundReceipt: PushPayload?
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// First launch: ask permission (Apple's HIG — ask when value is clear), then register.
    /// Subsequent launches: re-register if already authorized so reinstalls/token rotation self-heal.
    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                authorizationStatus = granted ? .authorized : .denied
                if granted { UIApplication.shared.registerForRemoteNotifications() }
            } catch {
                pushLog.error("authorization request failed: \(error.localizedDescription, privacy: .public)")
            }
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Re-registers with APNs if permission is (now) granted, without ever
    /// prompting. Called on foreground so flipping notifications on in the
    /// Settings app takes effect without a relaunch.
    func registerIfAuthorized() async {
        await refreshAuthorizationStatus()
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }

    #if DEBUG
    /// Provisional auth is granted silently (no prompt) — used only to exercise the
    /// receive path in the Simulator, where the permission alert can't be tapped.
    func requestProvisionalForTesting() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound, .provisional])
        await refreshAuthorizationStatus()
        UIApplication.shared.registerForRemoteNotifications()
    }
    #endif

    func setBadgeCount(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(max(0, count))
    }

    // Called by the app delegate.
    func didRegister(tokenData: Data) {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        pushLog.info("registered apns device token")
    }

    func didReceiveTap(_ payload: PushPayload) {
        lastTap = payload
    }

    func didReceiveForeground(_ payload: PushPayload) {
        lastForegroundReceipt = payload
    }
}

/// Bridges UIKit push callbacks into `PushService`. Wired via `UIApplicationDelegateAdaptor`.
/// `@MainActor` so the conformance matches the SDK's main-actor delegate methods.
@MainActor
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushService.shared.didRegister(tokenData: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushLog.error("remote registration failed: \(error.localizedDescription, privacy: .public)")
    }

    // Foreground: still show the banner (and let the payload's badge apply),
    // and hand the payload to the UI so the feed refreshes to match it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if let payload = PushPayload(userInfo: notification.request.content.userInfo) {
            await MainActor.run { PushService.shared.didReceiveForeground(payload) }
        }
        return [.banner, .list, .sound, .badge]
    }

    // Tap: deep-link to the relevant content. Extract the Sendable payload off the
    // main actor, then hand it over.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = PushPayload(userInfo: response.notification.request.content.userInfo)
        guard let payload else { return }
        await MainActor.run { PushService.shared.didReceiveTap(payload) }
    }
}
