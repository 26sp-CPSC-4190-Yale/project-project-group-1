import APNS
import APNSCore
import Fluent
import Foundation
import Vapor
import VaporAPNS

struct NotificationService {
    enum NotificationType {
        static let nudge = "nudge"
        static let friendRequest = "friend_request"
        static let friendAccepted = "friend_accepted"
        static let friendshipUpdated = "friendship_updated"
        static let friendVerified = "friend_verified"
        static let sessionStartingSoon = "session_starting_soon"
        static let sessionLocked = "session_locked"
        static let sessionEnded = "session_ended"
        static let sessionJailbreak = "session_jailbreak"
        static let sessionProximityExit = "session_proximity_exit"
    }

    // silently no-ops if the user has no device token or APNs is not configured
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

        do {
            try await application.apns.client(.default).sendAlertNotification(
                notification,
                deviceToken: token
            )
        } catch {
            application.logger.warning("APNs alert push failed for user \(userID) (type=\(type)): \(error)")
        }
    }

    // silent content-available push, the WebSocket fallback that applies the shield when the client is backgrounded
    static func sendSilent(
        to userID: UUID,
        type: String,
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
        }

        let notification = APNSBackgroundNotification(
            expiration: .immediately,
            topic: bundleID,
            payload: SilentPayload(type: type)
        )

        do {
            try await application.apns.client(.default).sendBackgroundNotification(
                notification,
                deviceToken: token
            )
        } catch {
            application.logger.warning("APNs silent push failed for user \(userID) (type=\(type)): \(error)")
        }
    }

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

    // call from configure.swift, any missing APNs env var skips setup so local dev runs without credentials
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
