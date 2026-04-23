import Foundation

public struct SessionRecap: Codable, Sendable, Identifiable {
    public var id: UUID { sessionID }
    public let sessionID: UUID
    public let totalDurationSeconds: Int
    public let participantCount: Int
    public let jailbreakCount: Int
    public let completionRate: Double

    public init(
        sessionID: UUID,
        totalDurationSeconds: Int,
        participantCount: Int,
        jailbreakCount: Int,
        completionRate: Double
    ) {
        self.sessionID = sessionID
        self.totalDurationSeconds = totalDurationSeconds
        self.participantCount = participantCount
        self.jailbreakCount = jailbreakCount
        self.completionRate = completionRate
    }
}
