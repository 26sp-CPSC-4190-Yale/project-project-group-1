//
//  AppDelegate.swift
//  Unplugged.App
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import UIKit
import UserNotifications

/// Bridged into the SwiftUI app via `@UIApplicationDelegateAdaptor`. Handles APNs
/// registration and silent-push routing into `SessionOrchestrator`, which acts as
/// the fallback lock-engagement path when the WebSocket isn't connected.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by `UnpluggedApp` at launch so silent-push handlers can reach into the
    /// session orchestrator without going through the SwiftUI environment. Always
    /// set and read on the main actor — UIApplicationDelegate callbacks run there.
    @MainActor static var sharedContainer: DependencyContainer?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        let container = MainActor.assumeIsolated { Self.sharedContainer }
        Task {
            try? await container?.user.registerDeviceToken(hex)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Silent APNs is a fallback; main lock path is the WebSocket.
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        MainActor.assumeIsolated {
            if let type = userInfo["type"] as? String,
               let orchestrator = Self.sharedContainer?.sessionOrchestrator {
                orchestrator.handleRemotePayload(type: type, userInfo: userInfo)
            }
        }
        completionHandler(.newData)
    }
}
