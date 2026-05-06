import CoreLocation
import Foundation
import UnpluggedShared

struct SessionAPIService {
    let client: APIClient

    func createSession(
        title: String,
        durationSeconds: Int?,
        lockMode: SessionLockMode = .standard,
        location: CLLocationCoordinate2D? = nil
    ) async throws -> SessionResponse {
        let body = CreateSessionRequest(
            title: title,
            durationSeconds: durationSeconds,
            lockMode: lockMode,
            latitude: location?.latitude,
            longitude: location?.longitude
        )
        return try await client.send(.createSession(body))
    }

    func listSessions() async throws -> [SessionResponse] {
        try await client.send(.listSessions)
    }

    func listHistory(limit: Int? = nil, before: Date? = nil) async throws -> [SessionHistoryResponse] {
        try await client.send(.sessionHistory(limit: limit, before: before))
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

    func leaveSession(id: UUID) async throws {
        try await client.sendVoid(.leaveSession(id: id))
    }

    func updateMetadata(
        id: UUID,
        description: String? = nil,
        location: CLLocationCoordinate2D?
    ) async throws -> SessionResponse {
        let body = SessionMetadataRequest(
            description: description,
            latitude: location?.latitude,
            longitude: location?.longitude
        )
        return try await client.send(.updateSessionMetadata(id: id, body: body))
    }

    func setCoLockReady(id: UUID, isReady: Bool) async throws -> SessionResponse {
        try await client.send(.setCoLockReady(id: id, body: CoLockReadyRequest(isReady: isReady)))
    }

    func requestCoLockRelease(id: UUID) async throws -> SessionResponse {
        try await client.send(.requestCoLockRelease(id: id))
    }

    func approveCoLockRelease(id: UUID) async throws -> SessionResponse {
        try await client.send(.approveCoLockRelease(id: id))
    }

    func listPhotos(id: UUID) async throws -> [SessionMemoryPhotoResponse] {
        try await client.send(.listSessionPhotos(id: id))
    }

    func uploadPhoto(id: UUID, imageData: Data, thumbnailData: Data?, mimeType: String) async throws -> SessionMemoryPhotoResponse {
        let body = UploadSessionPhotoRequest(imageData: imageData, thumbnailData: thumbnailData, mimeType: mimeType)
        return try await client.send(.uploadSessionPhoto(id: id, body: body))
    }

    func deletePhoto(sessionID: UUID, photoID: UUID) async throws {
        try await client.sendVoid(.deleteSessionPhoto(id: sessionID, photoID: photoID))
    }

    func reportJailbreak(id: UUID, reason: String, detectedAt: Date = Date()) async throws {
        let body = ReportJailbreakRequest(reason: reason, detectedAt: detectedAt)
        try await client.sendVoid(.reportJailbreak(id: id, body: body))
    }

    func reportProximityExit(id: UUID) async throws {
        try await client.sendVoid(.reportProximityExit(id: id))
    }

    func reportShieldAttempt(
        id: UUID,
        reason: String = SessionExitReason.shieldActionAttempt,
        occurredAt: Date = Date()
    ) async throws {
        try await client.sendVoid(.reportShieldAttempt(
            id: id,
            body: ShieldActionAttemptRequest(reason: reason, occurredAt: occurredAt)
        ))
    }
}
