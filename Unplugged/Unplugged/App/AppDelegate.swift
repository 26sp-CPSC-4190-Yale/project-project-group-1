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
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by `UnpluggedApp` at launch so silent-push handlers can reach into the
    /// session orchestrator without going through the SwiftUI environment. Always
    /// set and read on the main actor — UIApplicationDelegate callbacks run there.
    @MainActor static var sharedContainer: DependencyContainer?

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
        Self.log.warning("APNs registration failed: \(String(describing: error), privacy: .public)")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // §74: validate the payload before dispatching. A missing or unknown `type`
        // means we shouldn't wake the session orchestrator.
        guard let type = userInfo["type"] as? String,
              Self.knownPayloadTypes.contains(type) else {
            completionHandler(.noData)
            return
        }

        MainActor.assumeIsolated {
            Self.sharedContainer?.sessionOrchestrator.handleRemotePayload(type: type, userInfo: userInfo)
        }
        // §73: report the actual outcome. `.newData` is appropriate because we did
        // update in-app state based on the payload; lying about "new data" when
        // nothing happened gets the app deprioritized by iOS background scheduling.
        completionHandler(.newData)
    }

    @objc private func appDidBecomeActive() {
        Task { await Self.syncDeviceToken() }
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
            log.warning("Device token upload failed; will retry on next foreground: \(String(describing: error), privacy: .public)")
        }
    }
}
