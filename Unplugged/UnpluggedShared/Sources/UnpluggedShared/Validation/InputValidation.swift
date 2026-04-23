public enum InputValidation {
    public static let usernameMinLength = 3
    public static let usernameMaxLength = 20
    public static let passwordMinLength = 8
    public static let sessionCodeLength = 6

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
}

