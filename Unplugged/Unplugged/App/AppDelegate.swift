//
//  AppDelegate.swift
//  Unplugged.App
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import UIKit
import UserNotifications
import os

/// Bridged into the SwiftUI app via `@UIApplicationDelegateAdaptor`. Handles APNs
/// registration and silent-push routing into `SessionOrchestrator`, which acts as
/// the fallback lock-engagement path when the WebSocket isn't connected.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by `UnpluggedApp` at launch so silent-push handlers can reach into the
    /// session orchestrator without going through the SwiftUI environment. Always
    /// set and read on the main actor — UIApplicationDelegate callbacks run there.
    @MainActor static var sharedContainer: DependencyContainer?

    // Backing os.Logger for APNs diagnostics. Goes through AppLogger.push on
    // hot paths (failures) so the kill switch silences this too. The raw
    // Logger is kept here only as a fallback — prefer AppLogger.push.
    private static let log = Logger(subsystem: "com.unplugged.app", category: "push")

    /// UserDefaults keys for the device-token retry path. If a registration upload
    /// fails on first launch (no network, server 500, auth not ready), we hold onto
    /// the hex and retry on the next `didBecomeActive` until it sticks.
    private enum Keys {
        static let pendingToken = "apns.pendingToken"
        static let registeredToken = "apns.registeredToken"
    }

    /// Silent-push `type` field is user-controlled — only values we actually handle
    /// should reach the orchestrator. Unknown types mean either a malformed payload
    /// or a newer server speaking a protocol this client doesn't know; either way,
    /// return `.noData` so iOS throttles future wakeups appropriately.
    private static let knownPayloadTypes: Set<String> = ["session_locked", "session_ended"]

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set the UNUserNotificationCenter delegate before launch finishes. If set
        // later, a tap that launched the app from a notification is lost because the
        // system has no one to deliver it to during app startup.
        UNUserNotificationCenter.current().delegate = self

        // Don't prompt for notification permission at launch — onboarding has an
        // explicit step for it with user-facing rationale. Double-prompting on every
        // launch trains users to deny (permission fatigue) and creates a race with
        // the onboarding flow.
        //
        // Calling registerForRemoteNotifications() unconditionally is safe: iOS only
        // activates APNs if the user has already granted notification permission, so
        // on a fresh install this is a no-op until onboarding completes. Once granted,
        // it ensures we get a device token on every subsequent launch.
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
        // Silent APNs is a fallback; main lock path is the WebSocket. Log for
        // diagnostics but don't surface to the user — they can't act on it.
        AppLogger.push.warning("APNs registration failed", error: error)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // §74: validate the payload before dispatching. A missing or unknown `type`
        // means we shouldn't wake the session orchestrator.
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
            // §73: report the actual outcome after the lifecycle work has run.
            // Completing before the shield attempt can let iOS suspend the app
            // before the background fallback does the thing it woke up to do.
            completionHandler(handled ? .newData : .noData)
        }
    }

    @objc private func appDidBecomeActive() {
        Task { await Self.syncDeviceToken() }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Present visible pushes while the app is in the foreground. Without this,
    /// iOS silently suppresses banners for alert payloads when the user is
    /// already in the app, so they only ever see them if they happen to be on
    /// the lock screen or home screen when the push arrives.
    ///
    /// Silent background payloads never flow through here — they hit
    /// `didReceiveRemoteNotification` instead — so anything reaching this
    /// method is an alert from `NotificationService.send()` that the user
    /// should see.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    /// Fires when the user taps a notification from the lock screen, banner, or
    /// notification center — regardless of whether the app was backgrounded,
    /// suspended, or cold-launched by the tap. If the payload carries a known
    /// session-lifecycle `type`, forward it to the orchestrator so shields
    /// apply even on a cold launch; otherwise just let the tap open the app.
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

    /// §72: retry device-token registration on failures. Called on every didBecomeActive
    /// so transient network/auth failures during initial registration heal automatically
    /// without the user reinstalling the app.
    @MainActor
    private static func syncDeviceToken() async {
        let defaults = UserDefaults.standard
        guard let hex = defaults.string(forKey: Keys.pendingToken) else { return }

        // If we've already registered this exact token, don't re-upload.
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
            // Leave pendingToken in place so the next didBecomeActive retries.
            AppLogger.push.warning("device token upload failed; will retry on next foreground", error: error)
        }
    }
}
