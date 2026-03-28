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

    public static func isValidPassword(_ password: String) -> Bool {
        password.count >= passwordMinLength
    }

    public static func isValidSessionCode(_ code: String) -> Bool {
        code.count == sessionCodeLength && code.allSatisfy { $0.isLetter || $0.isNumber }
    }
}

