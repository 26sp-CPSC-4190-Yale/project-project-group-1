import Foundation

public struct Session: Codable, Identifiable, Sendable {
    public let id: UUID
    public let code: String
    public let hostID: UUID
    public let state: RoomState
    public let title: String?
    public let description: String?
    public let durationSeconds: Int?
    public let lockMode: SessionLockMode
    public let startedAt: Date?
    public let lockedAt: Date?
    public let endsAt: Date?
    public let endedAt: Date?
    public let latitude: Double?
    public let longitude: Double?
    public let weather: SessionWeatherSnapshot?
    public let coLockStatus: SessionCoLockStatus?

    private enum CodingKeys: String, CodingKey {
        case id
        case code
        case hostID
        case state
        case title
        case description
        case durationSeconds
        case lockMode
        case startedAt
        case lockedAt
        case endsAt
        case endedAt
        case latitude
        case longitude
        case weather
        case coLockStatus
    }

    public init(
        id: UUID,
        code: String,
        hostID: UUID,
        state: RoomState,
        title: String? = nil,
        description: String? = nil,
        durationSeconds: Int? = nil,
        lockMode: SessionLockMode = .standard,
        startedAt: Date? = nil,
        lockedAt: Date? = nil,
        endsAt: Date? = nil,
        endedAt: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        weather: SessionWeatherSnapshot? = nil,
        coLockStatus: SessionCoLockStatus? = nil
    ) {
        self.id = id
        self.code = code
        self.hostID = hostID
        self.state = state
        self.title = title
        self.description = description
        self.durationSeconds = durationSeconds
        self.lockMode = lockMode
        self.startedAt = startedAt
        self.lockedAt = lockedAt
        self.endsAt = endsAt
        self.endedAt = endedAt
        self.latitude = latitude
        self.longitude = longitude
        self.weather = weather
        self.coLockStatus = coLockStatus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.code = try c.decode(String.self, forKey: .code)
        self.hostID = try c.decode(UUID.self, forKey: .hostID)
        self.state = try c.decode(RoomState.self, forKey: .state)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        self.lockMode = try c.decodeIfPresent(SessionLockMode.self, forKey: .lockMode) ?? .standard
        self.startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        self.lockedAt = try c.decodeIfPresent(Date.self, forKey: .lockedAt)
        self.endsAt = try c.decodeIfPresent(Date.self, forKey: .endsAt)
        self.endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        self.latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        self.weather = try c.decodeIfPresent(SessionWeatherSnapshot.self, forKey: .weather)
        self.coLockStatus = try c.decodeIfPresent(SessionCoLockStatus.self, forKey: .coLockStatus)
    }
}
