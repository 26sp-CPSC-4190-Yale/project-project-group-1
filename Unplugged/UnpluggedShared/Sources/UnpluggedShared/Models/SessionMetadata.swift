import Foundation

public struct SessionWeatherSnapshot: Codable, Sendable, Hashable {
    public let summary: String
    public let temperatureFahrenheit: Double?
    public let conditionSymbol: String?
    public let capturedAt: Date

    public init(
        summary: String,
        temperatureFahrenheit: Double? = nil,
        conditionSymbol: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.summary = summary
        self.temperatureFahrenheit = temperatureFahrenheit
        self.conditionSymbol = conditionSymbol
        self.capturedAt = capturedAt
    }
}

public struct SessionMemoryPhotoResponse: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let sessionID: UUID
    public let uploaderID: UUID
    public let mimeType: String
    public let byteCount: Int
    public let thumbnailData: Data?
    public let createdAt: Date

    public init(
        id: UUID,
        sessionID: UUID,
        uploaderID: UUID,
        mimeType: String,
        byteCount: Int,
        thumbnailData: Data? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.uploaderID = uploaderID
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.thumbnailData = thumbnailData
        self.createdAt = createdAt
    }
}

public struct SessionCoLockStatus: Codable, Sendable, Hashable {
    public let requiredApprovals: Int
    public let startReadyUserIDs: [UUID]
    public let releaseRequestedBy: UUID?
    public let releaseApprovalUserIDs: [UUID]

    public init(
        requiredApprovals: Int,
        startReadyUserIDs: [UUID] = [],
        releaseRequestedBy: UUID? = nil,
        releaseApprovalUserIDs: [UUID] = []
    ) {
        self.requiredApprovals = requiredApprovals
        self.startReadyUserIDs = startReadyUserIDs
        self.releaseRequestedBy = releaseRequestedBy
        self.releaseApprovalUserIDs = releaseApprovalUserIDs
    }
}

