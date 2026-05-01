import Foundation

public struct JailbreakEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let userID: UUID
    public let username: String
    public let detectedAt: Date
    public let reason: String?

    public init(id: UUID, userID: UUID, username: String, detectedAt: Date, reason: String? = nil) {
        self.id = id
        self.userID = userID
        self.username = username
        self.detectedAt = detectedAt
        self.reason = reason
    }
}

public struct SessionRecapResponse: Codable, Sendable, Identifiable {
    public var id: UUID { sessionID }
    public let sessionID: UUID
    public let title: String?
    public let description: String?
    public let startedAt: Date?
    public let endedAt: Date?
    public let durationSeconds: Int?
    public let actualFocusedSeconds: Int
    public let endedEarly: Bool
    public let participants: [ParticipantResponse]
    public let jailbreaks: [JailbreakEntry]
    public let completionRate: Double
    public let latitude: Double?
    public let longitude: Double?
    public let weather: SessionWeatherSnapshot?
    public let memoryPhotos: [SessionMemoryPhotoResponse]

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case title
        case description
        case startedAt
        case endedAt
        case durationSeconds
        case actualFocusedSeconds
        case endedEarly
        case participants
        case jailbreaks
        case completionRate
        case latitude
        case longitude
        case weather
        case memoryPhotos
    }

    public init(
        sessionID: UUID,
        title: String?,
        description: String? = nil,
        startedAt: Date?,
        endedAt: Date?,
        durationSeconds: Int?,
        actualFocusedSeconds: Int,
        endedEarly: Bool,
        participants: [ParticipantResponse],
        jailbreaks: [JailbreakEntry],
        completionRate: Double,
        latitude: Double? = nil,
        longitude: Double? = nil,
        weather: SessionWeatherSnapshot? = nil,
        memoryPhotos: [SessionMemoryPhotoResponse] = []
    ) {
        self.sessionID = sessionID
        self.title = title
        self.description = description
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.actualFocusedSeconds = actualFocusedSeconds
        self.endedEarly = endedEarly
        self.participants = participants
        self.jailbreaks = jailbreaks
        self.completionRate = completionRate
        self.latitude = latitude
        self.longitude = longitude
        self.weather = weather
        self.memoryPhotos = memoryPhotos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionID = try c.decode(UUID.self, forKey: .sessionID)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        self.endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        self.durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        self.actualFocusedSeconds = try c.decode(Int.self, forKey: .actualFocusedSeconds)
        self.endedEarly = try c.decode(Bool.self, forKey: .endedEarly)
        self.participants = try c.decode([ParticipantResponse].self, forKey: .participants)
        self.jailbreaks = try c.decode([JailbreakEntry].self, forKey: .jailbreaks)
        self.completionRate = try c.decode(Double.self, forKey: .completionRate)
        self.latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        self.weather = try c.decodeIfPresent(SessionWeatherSnapshot.self, forKey: .weather)
        self.memoryPhotos = try c.decodeIfPresent([SessionMemoryPhotoResponse].self, forKey: .memoryPhotos) ?? []
    }
}
