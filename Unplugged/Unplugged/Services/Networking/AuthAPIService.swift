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
}
