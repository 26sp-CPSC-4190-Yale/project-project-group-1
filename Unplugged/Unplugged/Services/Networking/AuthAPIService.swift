//
//  AuthAPIService.swift
//  Unplugged.Services.Networking
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import UnpluggedShared

struct AuthAPIService {
    let client: APIClient

    func login(username: String, password: String) async throws -> AuthResponse {
        try await client.send(.login(LoginRequest(username: username, password: password)))
    }

    func register(username: String, password: String) async throws -> AuthResponse {
        try await client.send(.register(RegisterRequest(username: username, password: password)))
    }

    func signInWithApple(
        identityToken: String,
        authorizationCode: String? = nil,
        fullName: String? = nil,
        email: String? = nil
    ) async throws -> AuthResponse {
        let body = AppleSignInRequest(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            fullName: fullName,
            email: email
        )
        return try await client.send(.signInWithApple(body))
    }

    func signInWithGoogle(idToken: String) async throws -> AuthResponse {
        try await client.send(.signInWithGoogle(GoogleSignInRequest(idToken: idToken)))
    }
}
