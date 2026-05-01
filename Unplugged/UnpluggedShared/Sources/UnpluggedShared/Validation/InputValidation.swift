import Foundation

public enum InputValidation {
    public static let usernameMinLength = 3
    public static let usernameMaxLength = 20
    public static let passwordMinLength = 8
    public static let sessionCodeLength = 6
    public static let sessionTitleMaxLength = 80
    public static let sessionDescriptionMaxLength = 280
    public static let groupNameMaxLength = 50
    public static let reportReasonMaxLength = 64
    public static let reportDetailsMaxLength = 1_000
    public static let jailbreakReasonMaxLength = 64
    public static let maxPhotoBytes = 1_500_000
    public static let maxPhotoThumbnailBytes = 160_000

    public static func isValidUsername(_ username: String) -> Bool {
        let length = username.count
        guard length >= usernameMinLength, length <= usernameMaxLength else { return false }
        return username.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    // 8+ chars and 3 of 4 classes, intentionally not all 4 nor expiry-based since NIST warns those push predictable substitutions
    public static func isValidPassword(_ password: String) -> Bool {
        guard password.count >= passwordMinLength else { return false }
        var classes = 0
        if password.contains(where: { $0.isLowercase }) { classes += 1 }
        if password.contains(where: { $0.isUppercase }) { classes += 1 }
        if password.contains(where: { $0.isNumber }) { classes += 1 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }) { classes += 1 }
        return classes >= 3
    }

    // used by server 400 and client helper text, keep the two surfaces identical
    public static let passwordRequirementsMessage =
        "Password must be at least 8 characters and include three of: lowercase, uppercase, numbers, symbols."

    public static func isValidSessionCode(_ code: String) -> Bool {
        code.count == sessionCodeLength && code.allSatisfy { $0.isLetter || $0.isNumber }
    }

    public static func normalizedSessionCode(_ code: String) -> String {
        String(code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isLetter || $0.isNumber }
            .prefix(sessionCodeLength))
            .uppercased()
    }

    public static func normalizedUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func usernameLookupKey(_ username: String) -> String {
        normalizedUsername(username).lowercased()
    }

    public static func normalizedOptionalText(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    public static func isValidSessionTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= sessionTitleMaxLength
    }

    public static func isValidSessionDescription(_ description: String?) -> Bool {
        guard let description else { return true }
        return description.trimmingCharacters(in: .whitespacesAndNewlines).count <= sessionDescriptionMaxLength
    }

    public static func isValidDurationSeconds(_ durationSeconds: Int?) -> Bool {
        guard let durationSeconds else { return true }
        return durationSeconds > 0 && durationSeconds <= 60 * 60 * 24
    }

    public static func isValidLatitude(_ latitude: Double?) -> Bool {
        guard let latitude else { return true }
        return latitude >= -90 && latitude <= 90
    }

    public static func isValidLongitude(_ longitude: Double?) -> Bool {
        guard let longitude else { return true }
        return longitude >= -180 && longitude <= 180
    }

    public static func isValidJailbreakReason(_ reason: String) -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= jailbreakReasonMaxLength
    }

    public static func normalizedJailbreakReason(_ reason: String) -> String {
        normalizedOptionalText(reason, maxLength: jailbreakReasonMaxLength) ?? "unknown"
    }

    public static func normalizedAPNsToken(_ raw: String) -> String? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace && $0 != "<" && $0 != ">" }
        let isHex = normalized.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdef").contains($0)
        }

        guard normalized.count >= 32,
              normalized.count.isMultiple(of: 2),
              isHex else {
            return nil
        }
        return normalized
    }
}
