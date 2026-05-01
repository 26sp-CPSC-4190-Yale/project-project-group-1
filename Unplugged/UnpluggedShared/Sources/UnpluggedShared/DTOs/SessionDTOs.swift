import Foundation

public struct CreateSessionRequest: Codable, Sendable {
    public let title: String
    public let description: String?
    public let durationSeconds: Int?
    public let lockMode: SessionLockMode
    public let latitude: Double?
    public let longitude: Double?
    public let weather: SessionWeatherSnapshot?

    private enum CodingKeys: String, CodingKey {
        case title
        case description
        case durationSeconds
        case lockMode
        case latitude
        case longitude
        case weather
    }

    public init(
        title: String,
        durationSeconds: Int?,
        description: String? = nil,
        lockMode: SessionLockMode = .standard,
        latitude: Double? = nil,
        longitude: Double? = nil,
        weather: SessionWeatherSnapshot? = nil
    ) {
        self.title = title
        self.description = description
        self.durationSeconds = durationSeconds
        self.lockMode = lockMode
        self.latitude = latitude
        self.longitude = longitude
        self.weather = weather
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try c.decode(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        self.lockMode = try c.decodeIfPresent(SessionLockMode.self, forKey: .lockMode) ?? .standard
        self.latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        self.weather = try c.decodeIfPresent(SessionWeatherSnapshot.self, forKey: .weather)
    }
}

public struct StartSessionRequest: Codable, Sendable {
    public init() {}
}

public struct SessionMetadataRequest: Codable, Sendable {
    public let description: String?
    public let latitude: Double?
    public let longitude: Double?
    public let weather: SessionWeatherSnapshot?

    public init(description: String? = nil, latitude: Double? = nil, longitude: Double? = nil, weather: SessionWeatherSnapshot? = nil) {
        self.description = description
        self.latitude = latitude
        self.longitude = longitude
        self.weather = weather
    }
}

public struct EndSessionRequest: Codable, Sendable {
    public init() {}
}

public struct JoinSessionRequest: Codable, Sendable {
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

public struct ReportJailbreakRequest: Codable, Sendable {
    public let reason: String
    public let detectedAt: Date

    public init(reason: String, detectedAt: Date = Date()) {
        self.reason = reason
        self.detectedAt = detectedAt
    }
}

public struct SessionResponse: Codable, Sendable, Identifiable {
    public var id: UUID { session.id }
    public let session: Session
    public let participants: [ParticipantResponse]
    public let memoryPhotos: [SessionMemoryPhotoResponse]

    private enum CodingKeys: String, CodingKey {
        case session
        case participants
        case memoryPhotos
    }

    public init(
        session: Session,
        participants: [ParticipantResponse],
        memoryPhotos: [SessionMemoryPhotoResponse] = []
    ) {
        self.session = session
        self.participants = participants
        self.memoryPhotos = memoryPhotos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.session = try c.decode(Session.self, forKey: .session)
        self.participants = try c.decode([ParticipantResponse].self, forKey: .participants)
        self.memoryPhotos = try c.decodeIfPresent([SessionMemoryPhotoResponse].self, forKey: .memoryPhotos) ?? []
    }
}

public struct CoLockReadyRequest: Codable, Sendable {
    public let isReady: Bool

    public init(isReady: Bool = true) {
        self.isReady = isReady
    }
}

public struct CoLockReleaseRequest: Codable, Sendable {
    public init() {}
}

public struct UploadSessionPhotoRequest: Codable, Sendable {
    public let imageData: Data
    public let thumbnailData: Data?
    public let mimeType: String

    public init(imageData: Data, thumbnailData: Data? = nil, mimeType: String) {
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.mimeType = mimeType
    }
}

public struct ShieldActionAttemptRequest: Codable, Sendable {
    public let reason: String
    public let occurredAt: Date

    public init(reason: String = SessionExitReason.shieldActionAttempt, occurredAt: Date = Date()) {
        self.reason = reason
        self.occurredAt = occurredAt
    }
}

public struct ParticipantResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let userID: UUID
    public let username: String
    public let status: ParticipantStatus
    public let joinedAt: Date?
    public let isHost: Bool

    public init(
        id: UUID,
        userID: UUID,
        username: String,
        status: ParticipantStatus,
        joinedAt: Date? = nil,
        isHost: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.username = username
        self.status = status
        self.joinedAt = joinedAt
        self.isHost = isHost
    }
}

public struct SessionHistoryResponse: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let title: String?
    public let description: String?
    public let startedAt: Date?
    public let endedAt: Date?
    public let durationSeconds: Int?
    public let participantCount: Int
    public let latitude: Double?
    public let longitude: Double?
    public let weather: SessionWeatherSnapshot?
    public let memoryPhotos: [SessionMemoryPhotoResponse]
    public let actualFocusedSeconds: Int?
    public let leftEarly: Bool
    public let leftAt: Date?
    public let leaveReason: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case startedAt
        case endedAt
        case durationSeconds
        case participantCount
        case latitude
        case longitude
        case weather
        case memoryPhotos
        case actualFocusedSeconds
        case leftEarly
        case leftAt
        case leaveReason
    }

    public init(
        id: UUID,
        title: String?,
        description: String? = nil,
        startedAt: Date?,
        endedAt: Date?,
        durationSeconds: Int?,
        participantCount: Int,
        latitude: Double? = nil,
        longitude: Double? = nil,
        weather: SessionWeatherSnapshot? = nil,
        memoryPhotos: [SessionMemoryPhotoResponse] = [],
        actualFocusedSeconds: Int? = nil,
        leftEarly: Bool = false,
        leftAt: Date? = nil,
        leaveReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.participantCount = participantCount
        self.latitude = latitude
        self.longitude = longitude
        self.weather = weather
        self.memoryPhotos = memoryPhotos
        self.actualFocusedSeconds = actualFocusedSeconds
        self.leftEarly = leftEarly
        self.leftAt = leftAt
        self.leaveReason = leaveReason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        self.endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        self.durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        self.participantCount = try c.decode(Int.self, forKey: .participantCount)
        self.latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        self.weather = try c.decodeIfPresent(SessionWeatherSnapshot.self, forKey: .weather)
        self.memoryPhotos = try c.decodeIfPresent([SessionMemoryPhotoResponse].self, forKey: .memoryPhotos) ?? []
        self.actualFocusedSeconds = try c.decodeIfPresent(Int.self, forKey: .actualFocusedSeconds)
        self.leftEarly = try c.decodeIfPresent(Bool.self, forKey: .leftEarly) ?? false
        self.leftAt = try c.decodeIfPresent(Date.self, forKey: .leftAt)
        self.leaveReason = try c.decodeIfPresent(String.self, forKey: .leaveReason)
    }
}
