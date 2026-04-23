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

/// APNs response reasons that mean the stored device token is permanently
/// useless — Apple has told us the token has been revoked (app uninstalled,
/// device restored, etc). When we see these we must clear the token from
/// the user row so we don't keep spamming APNs with a dead address.
///
/// `ErrorReason` is Hashable, so we use Set containment against the public
/// static factory values. The underlying `Reason` enum is internal to
/// APNSCore, so this is the stable public surface.
private let invalidAPNSTokenReasons: Set<APNSError.ErrorReason> = [
    .badDeviceToken,
    .unregistered,
    .deviceTokenNotForTopic
]

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
        static let sessionProximityExit = "session_proximity_exit"
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

        // Must match the iOS app's `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode
        // project. APNs drops any push whose topic doesn't match the bundle ID
        // on the registered device token (`DeviceTokenNotForTopic`), so a typo
        // here silently breaks every background push.
        let bundleID = Environment.get("APNS_BUNDLE_ID") ?? "com.unplugged"

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

        do {
            try await application.apns.client(.default).sendAlertNotification(
                notification,
                deviceToken: token
            )
        } catch {
            application.logger.warning("APNs alert push failed for user \(userID) (type=\(type)): \(error)")
            await Self.clearTokenIfInvalid(error: error, userID: userID, on: db, application: application)
        }
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

        // Must match the iOS app's `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode
        // project. APNs drops any push whose topic doesn't match the bundle ID
        // on the registered device token (`DeviceTokenNotForTopic`), so a typo
        // here silently breaks every background push.
        let bundleID = Environment.get("APNS_BUNDLE_ID") ?? "com.unplugged"

        struct SilentPayload: Codable & Sendable {
            let type: String
            let sessionID: String
            let endsAt: String?
        }

        let endsAtString = endsAt.map { ISO8601DateFormatter().string(from: $0) }

        let notification = APNSBackgroundNotification(
            expiration: .immediately,
            topic: bundleID,
            payload: SilentPayload(type: type, sessionID: sessionID.uuidString, endsAt: endsAtString)
        )

        do {
            try await application.apns.client(.default).sendBackgroundNotification(
                notification,
                deviceToken: token
            )
        } catch {
            application.logger.warning("APNs silent push failed for user \(userID) (type=\(type), session=\(sessionID)): \(error)")
            await Self.clearTokenIfInvalid(error: error, userID: userID, on: db, application: application)
        }
    }

    /// Inspect an APNs send error and, if Apple has told us the device token is
    /// permanently invalid, clear it from the user row. Any subsequent push
    /// attempts then short-circuit at the `user.deviceToken == nil` guard
    /// instead of repeatedly hitting APNs with a dead address.
    private static func clearTokenIfInvalid(
        error: Error,
        userID: UUID,
        on db: Database,
        application: Application
    ) async {
        guard let apnsError = error as? APNSError,
              let reason = apnsError.reason,
              invalidAPNSTokenReasons.contains(reason)
        else { return }

        do {
            guard let user = try await UserModel.find(userID, on: db) else { return }
            guard user.deviceToken != nil else { return }
            user.deviceToken = nil
            try await user.save(on: db)
            application.logger.info(
                "cleared invalid APNs device token for user \(userID) after \(reason.reason)"
            )
        } catch {
            application.logger.warning("failed to clear invalid APNs token for user \(userID): \(error)")
        }
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
