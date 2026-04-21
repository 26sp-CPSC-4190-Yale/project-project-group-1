//
//  InputValidation.swift
//  UnpluggedShared.Validation
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

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

    /// Password strength rules.
    ///
    /// We require 8+ characters and at least three of the four character classes
    /// (lower, upper, digit, symbol). This rejects the obvious offenders — "password",
    /// "12345678", "aaaaaaaa" — without pushing users into the impossible-to-remember
    /// territory that NIST explicitly warns against. We deliberately do *not* mandate
    /// every class or a rotating expiry; those patterns harm security in practice by
    /// pushing users to predictable substitutions.
    public static func isValidPassword(_ password: String) -> Bool {
        guard password.count >= passwordMinLength else { return false }
        var classes = 0
        if password.contains(where: { $0.isLowercase }) { classes += 1 }
        if password.contains(where: { $0.isUppercase }) { classes += 1 }
        if password.contains(where: { $0.isNumber }) { classes += 1 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }) { classes += 1 }
        return classes >= 3
    }

    /// Human-readable explanation of the rules — used as the 400 response and the
    /// client-side helper text so both surfaces say exactly the same thing.
    public static let passwordRequirementsMessage =
        "Password must be at least 8 characters and include three of: lowercase, uppercase, numbers, symbols."

    public static func isValidSessionCode(_ code: String) -> Bool {
        code.count == sessionCodeLength && code.allSatisfy { $0.isLetter || $0.isNumber }
    }
}

