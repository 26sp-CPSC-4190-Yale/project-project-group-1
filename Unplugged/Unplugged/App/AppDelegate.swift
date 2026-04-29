import UIKit
import UserNotifications
import UnpluggedShared

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor static var sharedContainer: DependencyContainer?

    private enum Keys {
        static let pendingToken = "apns.pendingToken"
        static let registeredToken = "apns.registeredToken"
        static let registeredUserID = "apns.registeredUserID"
    }

    // remote notification type is user controlled, only dispatch values we actually handle
    private static let sessionPayloadTypes: Set<String> = [
        "session_locked",
        "session_ended",
        "session_jailbreak",
        "session_proximity_exit",
        "session_starting_soon"
    ]
    private static let friendRefreshPayloadTypes: Set<String> = [
        "friend_request",
        "friend_accepted",
        "friendship_updated",
        "friend_verified"
    ]
    private static let knownPayloadTypes = sessionPayloadTypes
        .union(friendRefreshPayloadTypes)
        .union(["nudge"])

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
        AppLogger.push.info(
            "APNs device token received",
            context: ["token_suffix": Self.tokenSuffix(hex)]
        )
        Task { await Self.syncDeviceToken() }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLogger.push.warning("APNs registration failed", error: error)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Self.logPushReceived(source: "background_fetch", userInfo: userInfo)

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
            if Self.friendRefreshPayloadTypes.contains(type) {
                Self.postFriendsDidChange()
                completionHandler(.newData)
                return
            }

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

    @MainActor
    static func markDeviceTokenNeedsAccountSync() {
        let defaults = UserDefaults.standard
        if let registeredToken = defaults.string(forKey: Keys.registeredToken) {
            defaults.set(registeredToken, forKey: Keys.pendingToken)
        }
        defaults.removeObject(forKey: Keys.registeredToken)
        defaults.removeObject(forKey: Keys.registeredUserID)
    }

    // MARK: - UNUserNotificationCenterDelegate

    // without this, iOS suppresses banners for alert payloads while the app is foregrounded
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Self.logPushReceived(source: "foreground_alert", userInfo: notification.request.content.userInfo)
        Self.handleFriendNotification(userInfo: notification.request.content.userInfo)
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        Self.logPushReceived(
            source: "notification_response",
            userInfo: userInfo,
            context: ["action": response.actionIdentifier]
        )
        guard let type = userInfo["type"] as? String,
              Self.knownPayloadTypes.contains(type) else {
            completionHandler()
            return
        }

        Task { @MainActor in
            if Self.friendRefreshPayloadTypes.contains(type) {
                Self.postFriendsDidChange()
                completionHandler()
                return
            }

            _ = await Self.sharedContainer?.sessionOrchestrator.handleRemotePayload(
                type: type,
                userInfo: userInfo
            )
            completionHandler()
        }
    }

    @MainActor
    static func syncDeviceToken() async {
        let defaults = UserDefaults.standard
        let pendingToken = defaults.string(forKey: Keys.pendingToken)
        let registeredToken = defaults.string(forKey: Keys.registeredToken)
        guard let hex = pendingToken ?? registeredToken else { return }

        guard let container = sharedContainer else {
            AppLogger.push.debug("device token sync deferred: dependency container unavailable")
            return
        }

        guard container.cache.readCachedToken() != nil else {
            AppLogger.push.debug("device token sync deferred: no cached auth token")
            return
        }

        let currentUserID = container.cache.readUser()?.id.uuidString ?? "<unknown>"
        if pendingToken == nil,
           registeredToken == hex,
           defaults.string(forKey: Keys.registeredUserID) == currentUserID {
            defaults.removeObject(forKey: Keys.pendingToken)
            return
        }

        do {
            try await container.user.registerDeviceToken(hex)
            defaults.set(hex, forKey: Keys.registeredToken)
            defaults.set(currentUserID, forKey: Keys.registeredUserID)
            defaults.removeObject(forKey: Keys.pendingToken)
            AppLogger.push.info(
                "device token uploaded",
                context: [
                    "user_id": currentUserID,
                    "token_suffix": Self.tokenSuffix(hex)
                ]
            )
        } catch {
            AppLogger.push.warning("device token upload failed; will retry on next foreground", error: error)
        }
    }

    private static func handleFriendNotification(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String,
              friendRefreshPayloadTypes.contains(type) else { return }
        Task { @MainActor in
            postFriendsDidChange()
        }
    }

    @MainActor
    private static func postFriendsDidChange() {
        NotificationCenter.default.post(name: .unpluggedFriendsDidChange, object: nil)
    }

    private static func logPushReceived(
        source: String,
        userInfo: [AnyHashable: Any],
        context extraContext: [String: Any] = [:]
    ) {
        let type = userInfo["type"] as? String ?? "<missing>"
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        let alert = aps?["alert"] != nil
        var context: [String: Any] = [
            "source": source,
            "type": type,
            "known": knownPayloadTypes.contains(type),
            "alert": alert,
            "content_available": aps?["content-available"] as? Int ?? 0
        ]
        extraContext.forEach { context[$0.key] = $0.value }
        AppLogger.push.notice("remote push received", context: context)
    }

    private static func tokenSuffix(_ token: String) -> String {
        String(token.suffix(8))
    }
}

extension Notification.Name {
    static let unpluggedFriendsDidChange = Notification.Name("com.unplugged.app.friends.didChange")
}
