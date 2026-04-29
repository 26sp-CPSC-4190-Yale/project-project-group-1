import APNS
import APNSCore
import Fluent
import Foundation
import Vapor
import VaporAPNS

struct NotificationService {
    private static let defaultBundleID = "com.unplugged"
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

    // alert push; logs every skip/send path so notification delivery failures are diagnosable
    static func send(
        to userID: UUID,
        title: String,
        body: String,
        type: String,
        on db: Database,
        application: Application
    ) async {
        guard let token = await deviceToken(
            for: userID,
            channel: "alert",
            type: type,
            on: db,
            application: application
        ) else { return }

        let bundleID = apnsBundleID()

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
            application.logger.info("APNs alert push sending", metadata: [
                "user_id": "\(userID)",
                "type": "\(type)",
                "topic": "\(bundleID)",
                "token_suffix": "\(tokenSuffix(token))"
            ])
            try await application.apns.client(.default).sendAlertNotification(
                notification,
                deviceToken: token
            )
            application.logger.info("APNs alert push sent", metadata: [
                "user_id": "\(userID)",
                "type": "\(type)",
                "topic": "\(bundleID)",
                "token_suffix": "\(tokenSuffix(token))"
            ])
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
        guard let token = await deviceToken(
            for: userID,
            channel: "silent",
            type: type,
            on: db,
            application: application
        ) else { return }

        let bundleID = apnsBundleID()

        struct SilentPayload: Codable & Sendable {
            let type: String
        }

        let notification = APNSBackgroundNotification(
            expiration: .immediately,
            topic: bundleID,
            payload: SilentPayload(type: type)
        )

        do {
            application.logger.info("APNs silent push sending", metadata: [
                "user_id": "\(userID)",
                "type": "\(type)",
                "topic": "\(bundleID)",
                "token_suffix": "\(tokenSuffix(token))"
            ])
            try await application.apns.client(.default).sendBackgroundNotification(
                notification,
                deviceToken: token
            )
            application.logger.info("APNs silent push sent", metadata: [
                "user_id": "\(userID)",
                "type": "\(type)",
                "topic": "\(bundleID)",
                "token_suffix": "\(tokenSuffix(token))"
            ])
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
        guard let token = await deviceToken(
            for: userID,
            channel: "silent",
            type: type,
            on: db,
            application: application
        ) else { return }

        let bundleID = apnsBundleID()

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
            application.logger.info("APNs silent push sending", metadata: [
                "user_id": "\(userID)",
                "type": "\(type)",
                "session_id": "\(sessionID)",
                "topic": "\(bundleID)",
                "token_suffix": "\(tokenSuffix(token))"
            ])
            try await application.apns.client(.default).sendBackgroundNotification(
                notification,
                deviceToken: token
            )
            application.logger.info("APNs silent push sent", metadata: [
                "user_id": "\(userID)",
                "type": "\(type)",
                "session_id": "\(sessionID)",
                "topic": "\(bundleID)",
                "token_suffix": "\(tokenSuffix(token))"
            ])
        } catch {
            application.logger.warning("APNs silent push failed for user \(userID) (type=\(type), session=\(sessionID)): \(error)")
        }
    }

    private static func deviceToken(
        for userID: UUID,
        channel: String,
        type: String,
        on db: Database,
        application: Application
    ) async -> String? {
        guard application.isAPNSConfigured else {
            application.logger.warning("APNs \(channel) push skipped: APNs not configured", metadata: [
                "user_id": "\(userID)",
                "type": "\(type)"
            ])
            return nil
        }

        do {
            guard let user = try await UserModel.find(userID, on: db) else {
                application.logger.warning("APNs \(channel) push skipped: recipient user not found", metadata: [
                    "user_id": "\(userID)",
                    "type": "\(type)"
                ])
                return nil
            }
            guard let token = user.deviceToken, !token.isEmpty else {
                application.logger.warning("APNs \(channel) push skipped: recipient has no device token", metadata: [
                    "user_id": "\(userID)",
                    "type": "\(type)"
                ])
                return nil
            }
            return token
        } catch {
            application.logger.error("APNs \(channel) push skipped: recipient lookup failed for user \(userID) (type=\(type)): \(error)")
            return nil
        }
    }

    static func apnsBundleID() -> String {
        let trimmed = Environment.get("APNS_BUNDLE_ID")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return defaultBundleID
    }

    private static func tokenSuffix(_ token: String) -> String {
        String(token.suffix(8))
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
            let rawPrivateKey = Environment.get("APNS_PRIVATE_KEY"),
            let keyID = Environment.get("APNS_KEY_ID"),
            let teamID = Environment.get("APNS_TEAM_ID")
        else {
            logger.warning("[APNs] Skipping APNs setup — APNS_PRIVATE_KEY, APNS_KEY_ID, or APNS_TEAM_ID not set.")
            return
        }

        let privateKey = rawPrivateKey.replacingOccurrences(of: "\\n", with: "\n")
        let rawEnvironment = Environment.get("APNS_ENVIRONMENT")?.lowercased()
        let useProduction: Bool
        switch rawEnvironment {
        case "production":
            useProduction = true
        case "development", "sandbox":
            useProduction = false
        default:
            useProduction = environment == .production
        }
        let apnsEnv: APNSEnvironment = useProduction ? .production : .development

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
        let envName = useProduction ? "production" : "development"
        logger.info("[APNs] Configured for \(envName).", metadata: [
            "topic": "\(NotificationService.apnsBundleID())"
        ])
    }
}
