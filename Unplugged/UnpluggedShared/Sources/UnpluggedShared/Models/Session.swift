import Foundation

public struct Session: Codable, Identifiable, Sendable {
    public let id: UUID
    public let code: String
    public let hostID: UUID
    public let state: RoomState
    public let title: String?
    public let durationSeconds: Int?
    public let startedAt: Date?
    public let lockedAt: Date?
    public let endsAt: Date?
    public let endedAt: Date?
    public let latitude: Double?
    public let longitude: Double?

    public init(
        id: UUID,
        code: String,
        hostID: UUID,
        state: RoomState,
        title: String? = nil,
        durationSeconds: Int? = nil,
        startedAt: Date? = nil,
        lockedAt: Date? = nil,
        endsAt: Date? = nil,
        endedAt: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.code = code
        self.hostID = hostID
        self.state = state
        self.title = title
        self.durationSeconds = durationSeconds
        self.startedAt = startedAt
        self.lockedAt = lockedAt
        self.endsAt = endsAt
        self.endedAt = endedAt
        self.latitude = latitude
        self.longitude = longitude
    }
}
