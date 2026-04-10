//
//  NotificationService.swift
//  UnpluggedServer.Services
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import APNS
import APNSCore
import Fluent
import Foundation
import Vapor
import VaporAPNS

struct NotificationService {
    // iOS app uses these to route incoming pushes
    enum NotificationType {
        static let nudge = "nudge"
        static let friendRequest = "friend_request"
        static let friendAccepted = "friend_accepted"
        static let friendVerified = "friend_verified"
        static let sessionStartingSoon = "session_starting_soon"
        static let sessionLocked = "session_locked"
        static let sessionEnded = "session_ended"
        static let sessionJailbreak = "session_jailbreak"
    }

    /// Send a visible push notification to a user.
    /// No-op if the user has no device token or APNs is not configured.
    static func send(
        to userID: UUID,
        title: String,
        body: String,
        type: String,
        on db: Database,
        application: Application
    ) async {
        guard application.isAPNSConfigured,
              let user = try? await UserModel.find(userID, on: db),
              let token = user.deviceToken
        else { return }

        let bundleID = Environment.get("APNS_BUNDLE_ID") ?? "com.unplugged.app"

        struct NotificationPayload: Codable & Sendable {
            let type: String
        }

        let notification = APNSAlertNotification(
            alert: APNSAlertNotificationContent(
                title: .raw(title),
                body: .raw(body)
            ),
            expiration: .immediately,
            priority: .immediately,
            topic: bundleID,
            payload: NotificationPayload(type: type)
        )

        try? await application.apns.client(.default).sendAlertNotification(
            notification,
            deviceToken: token
        )
    }

    /// Send a silent background push (content-available: 1) carrying a lifecycle event.
    /// Used by session start/end broadcast so clients apply the shield even when
    /// the WebSocket is not currently connected (e.g. backgrounded app).
    static func sendSilent(
        to userID: UUID,
        type: String,
        sessionID: UUID,
        endsAt: Date? = nil,
        on db: Database,
        application: Application
    ) async {
        guard application.isAPNSConfigured,
              let user = try? await UserModel.find(userID, on: db),
              let token = user.deviceToken
        else { return }

        let bundleID = Environment.get("APNS_BUNDLE_ID") ?? "com.unplugged.app"

        struct SilentPayload: Codable & Sendable {
            let type: String
            let sessionID: String
            let endsAt: Date?
        }

        let notification = APNSBackgroundNotification(
            expiration: .immediately,
            topic: bundleID,
            payload: SilentPayload(type: type, sessionID: sessionID.uuidString, endsAt: endsAt)
        )

        try? await application.apns.client(.default).sendBackgroundNotification(
            notification,
            deviceToken: token
        )
    }
}

// MARK: - APNs setup

private struct APNSConfiguredKey: StorageKey {
    typealias Value = Bool
}

extension Application {
    var isAPNSConfigured: Bool {
        get { storage[APNSConfiguredKey.self] ?? false }
        set { storage[APNSConfiguredKey.self] = newValue }
    }

    /// call from configure.swift. reads credentials from environment variables.
    /// missing variable => APNs is skipped (safe for local dev without creds).
    func configureAPNS() throws {
        guard
            let privateKey = Environment.get("APNS_PRIVATE_KEY"),
            let keyID = Environment.get("APNS_KEY_ID"),
            let teamID = Environment.get("APNS_TEAM_ID")
        else {
            logger.warning("[APNs] Skipping APNs setup — APNS_PRIVATE_KEY, APNS_KEY_ID, or APNS_TEAM_ID not set.")
            return
        }

        let apnsEnv: APNSEnvironment = Environment.get("APNS_ENVIRONMENT") == "production"
            ? APNSEnvironment.production
            : APNSEnvironment.development

        apns.containers.use(
            APNSClientConfiguration(
                authenticationMethod: APNSClientConfiguration.AuthenticationMethod.jwt(
                    privateKey: try P256.Signing.PrivateKey(pemRepresentation: privateKey),
                    keyIdentifier: keyID,
                    teamIdentifier: teamID
                ),
                environment: apnsEnv
            ),
            eventLoopGroupProvider: .shared(eventLoopGroup),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder(),
            as: .default
        )

        isAPNSConfigured = true
        let envName = Environment.get("APNS_ENVIRONMENT") == "production" ? "production" : "development"
        logger.info("[APNs] Configured for \(envName).")
    }
}
