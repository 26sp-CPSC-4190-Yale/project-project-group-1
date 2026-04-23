import Foundation

public struct Participant: Codable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let userID: UUID
    public let username: String
    public let status: ParticipantStatus
    public let joinedAt: Date

    public init(id: UUID, sessionID: UUID, userID: UUID, username: String, status: ParticipantStatus, joinedAt: Date) {
        self.id = id
        self.sessionID = sessionID
        self.userID = userID
        self.username = username
        self.status = status
        self.joinedAt = joinedAt
    }
}
