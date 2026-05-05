import Foundation

enum ScreenTimeShared {
    static let appGroupID = "group.com.unplugged.app.shared"
    static let deviceActivityName = "unpluggedSession"
    static let managedSettingsStoreName = "unpluggedSession"
    static let shieldActionAttemptReason = "shield_action_attempt"

    private static let activeContextKey = "screenTime.activeContext"
    private static let pendingAttemptsKey = "screenTime.pendingShieldAttempts"

    struct ActiveContext: Codable, Equatable {
        let sessionID: UUID
        let bearerToken: String
        let baseURL: String
        let sessionTitle: String
        let lockMode: String
        let endsAt: Date?
        let isUnlimited: Bool
        let updatedAt: Date

        var shieldSubtitle: String {
            if isUnlimited || endsAt == nil {
                if lockMode == "coLock" {
                    return "This co-lock is active until everyone approves release."
                }
                return "This lock-in is active until you end it."
            }
            return "Stay present until this lock-in ends."
        }

        func isExpired(now: Date = Date()) -> Bool {
            guard !isUnlimited, let endsAt else { return false }
            return endsAt <= now
        }
    }

    struct PendingShieldAttempt: Codable, Equatable, Identifiable {
        let id: UUID
        let sessionID: UUID
        let reason: String
        let occurredAt: Date

        init(id: UUID = UUID(), sessionID: UUID, reason: String, occurredAt: Date = Date()) {
            self.id = id
            self.sessionID = sessionID
            self.reason = reason
            self.occurredAt = occurredAt
        }
    }

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    @discardableResult
    static func saveActiveContext(_ context: ActiveContext, defaults: UserDefaults? = Self.defaults) -> Bool {
        guard let defaults, let encoded = try? JSONEncoder.screenTime.encode(context) else {
            return false
        }
        defaults.set(encoded, forKey: activeContextKey)
        return true
    }

    static func loadActiveContext(defaults: UserDefaults? = Self.defaults) -> ActiveContext? {
        guard let data = defaults?.data(forKey: activeContextKey) else { return nil }
        return try? JSONDecoder.screenTime.decode(ActiveContext.self, from: data)
    }

    static func clearActiveContext(defaults: UserDefaults? = Self.defaults) {
        defaults?.removeObject(forKey: activeContextKey)
    }

    static func shieldAttemptURL(baseURL: String, sessionID: UUID) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let routePath = "sessions/\(sessionID.uuidString)/shield-attempt"
        components.path = basePath.isEmpty ? "/\(routePath)" : "/\(basePath)/\(routePath)"
        components.queryItems = nil
        return components.url
    }

    static func appendPendingShieldAttempt(_ attempt: PendingShieldAttempt, defaults: UserDefaults? = Self.defaults) {
        guard let defaults else { return }
        var attempts = pendingShieldAttempts(defaults: defaults)
        attempts.append(attempt)
        if attempts.count > 20 {
            attempts = Array(attempts.suffix(20))
        }
        savePendingShieldAttempts(attempts, defaults: defaults)
    }

    static func drainPendingShieldAttempts(defaults: UserDefaults? = Self.defaults) -> [PendingShieldAttempt] {
        guard let defaults else { return [] }
        let attempts = pendingShieldAttempts(defaults: defaults)
        defaults.removeObject(forKey: pendingAttemptsKey)
        return attempts
    }

    static func requeuePendingShieldAttempts(_ attempts: [PendingShieldAttempt], defaults: UserDefaults? = Self.defaults) {
        guard let defaults, !attempts.isEmpty else { return }
        let existing = pendingShieldAttempts(defaults: defaults)
        savePendingShieldAttempts(Array((attempts + existing).prefix(20)), defaults: defaults)
    }

    private static func pendingShieldAttempts(defaults: UserDefaults) -> [PendingShieldAttempt] {
        guard let data = defaults.data(forKey: pendingAttemptsKey),
              let attempts = try? JSONDecoder.screenTime.decode([PendingShieldAttempt].self, from: data) else {
            return []
        }
        return attempts
    }

    private static func savePendingShieldAttempts(_ attempts: [PendingShieldAttempt], defaults: UserDefaults) {
        guard let encoded = try? JSONEncoder.screenTime.encode(attempts) else { return }
        defaults.set(encoded, forKey: pendingAttemptsKey)
    }
}

private extension JSONEncoder {
    static var screenTime: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var screenTime: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
