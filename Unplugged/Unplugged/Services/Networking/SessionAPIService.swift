//
//  SessionAPIService.swift
//  Unplugged.Services.Networking
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import UnpluggedShared

struct SessionAPIService {
    let client: APIClient

    func createSession() async throws -> SessionResponse {
        try await client.send(.createSession(CreateSessionRequest()))
    }

    func listSessions() async throws -> [SessionResponse] {
        try await client.send(.listSessions)
    }

    func getSession(id: UUID) async throws -> SessionResponse {
        try await client.send(.getSession(id: id))
    }

    func joinSession(code: String) async throws -> SessionResponse {
        try await client.send(.joinSession(code: code))
    }
}
