import UIKit
import UserNotifications
import os

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor static var sharedContainer: DependencyContainer?

    private static let log = Logger(subsystem: "com.unplugged.app", category: "push")

    private enum Keys {
        static let pendingToken = "apns.pendingToken"
        static let registeredToken = "apns.registeredToken"
    }

    // silent push type is user controlled, only dispatch values we actually handle
    private static let knownPayloadTypes: Set<String> = ["session_locked", "session_ended"]

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // set before launch finishes, otherwise a tap that cold-launched the app has nowhere to be delivered
        UNUserNotificationCenter.current().delegate = self

        // onboarding owns the prompt, this is a no-op until the user grants permission there
        application.registerForRemoteNotifications()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: Keys.pendingToken)
        Task { await Self.syncDeviceToken() }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLogger.push.warning("APNs registration failed", error: error)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let type = userInfo["type"] as? String,
              Self.knownPayloadTypes.contains(type) else {
            AppLogger.push.warning(
                "silent push dropped: unknown or missing type",
                context: ["type": (userInfo["type"] as? String) ?? "<missing>"]
            )
            completionHandler(.noData)
            return
        }

        Task { @MainActor in
            let handled = await Self.sharedContainer?.sessionOrchestrator.handleRemotePayload(
                type: type,
                userInfo: userInfo
            ) ?? false
            // complete after the shield attempt runs, otherwise iOS can suspend before the fallback engages
            completionHandler(handled ? .newData : .noData)
        }
    }

    @objc private func appDidBecomeActive() {
        Task { await Self.syncDeviceToken() }
    }

    // MARK: - UNUserNotificationCenterDelegate

    // without this, iOS suppresses banners for alert payloads while the app is foregrounded
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        guard let type = userInfo["type"] as? String,
              Self.knownPayloadTypes.contains(type) else {
            completionHandler()
            return
        }

        Task { @MainActor in
            _ = await Self.sharedContainer?.sessionOrchestrator.handleRemotePayload(
                type: type,
                userInfo: userInfo
            )
            completionHandler()
        }
    }

    @MainActor
    private static func syncDeviceToken() async {
        let defaults = UserDefaults.standard
        guard let hex = defaults.string(forKey: Keys.pendingToken) else { return }

        if defaults.string(forKey: Keys.registeredToken) == hex {
            defaults.removeObject(forKey: Keys.pendingToken)
            return
        }

        guard let container = sharedContainer else { return }
        do {
            try await container.user.registerDeviceToken(hex)
            defaults.set(hex, forKey: Keys.registeredToken)
            defaults.removeObject(forKey: Keys.pendingToken)
        } catch {
            AppLogger.push.warning("device token upload failed; will retry on next foreground", error: error)
        }
    }
}
