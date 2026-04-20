//
//  SessionAPIService.swift
//  Unplugged.Services.Networking
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import CoreLocation
import Foundation
import UnpluggedShared

struct SessionAPIService {
    let client: APIClient

    func createSession(
        title: String,
        durationSeconds: Int,
        location: CLLocationCoordinate2D? = nil
    ) async throws -> SessionResponse {
        let body = CreateSessionRequest(
            title: title,
            durationSeconds: durationSeconds,
            latitude: location?.latitude,
            longitude: location?.longitude
        )
        return try await client.send(.createSession(body))
    }

    func listSessions() async throws -> [SessionResponse] {
        try await client.send(.listSessions)
    }

    func listHistory() async throws -> [SessionHistoryResponse] {
        try await client.send(.sessionHistory)
    }

    func getSession(id: UUID) async throws -> SessionResponse {
        try await client.send(.getSession(id: id))
    }

    func joinSession(id: UUID) async throws -> SessionResponse {
        try await client.send(.joinSession(id: id))
    }

    func joinSession(code: String) async throws -> SessionResponse {
        try await client.send(.joinSessionCode(code: code))
    }

    func startSession(id: UUID) async throws -> SessionResponse {
        try await client.send(.startSession(id: id))
    }

    func endSession(id: UUID) async throws -> SessionResponse {
        try await client.send(.endSession(id: id))
    }

    func reportJailbreak(id: UUID, reason: String, detectedAt: Date = Date()) async throws {
        let body = ReportJailbreakRequest(reason: reason, detectedAt: detectedAt)
        try await client.sendVoid(.reportJailbreak(id: id, body: body))
    }
}
