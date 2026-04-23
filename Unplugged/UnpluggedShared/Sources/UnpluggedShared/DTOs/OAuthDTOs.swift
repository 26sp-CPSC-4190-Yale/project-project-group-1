import Foundation

public struct AppleSignInRequest: Codable, Sendable {
    public let identityToken: String
    public let authorizationCode: String?
    public let fullName: String?
    public let email: String?

    public init(identityToken: String, authorizationCode: String? = nil, fullName: String? = nil, email: String? = nil) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.fullName = fullName
        self.email = email
    }
}

public struct GoogleSignInRequest: Codable, Sendable {
    public let idToken: String

    public init(idToken: String) {
        self.idToken = idToken
    }
}
