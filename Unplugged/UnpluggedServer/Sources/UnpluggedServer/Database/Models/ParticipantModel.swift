import Fluent
import UnpluggedShared
import Vapor

final class MemberModel: Model, @unchecked Sendable {
    static let schema = "member_info"
    static let proximityExitConfig = "proximity_exit"
    static let voluntaryExitConfig = "voluntary_exit"
    static let jailbreakConfig = "jailbreak"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userID: UUID

    @Field(key: "session_id")
    var sessionID: UUID

    @OptionalField(key: "config")
    var config: String?

    @Field(key: "joined_at")
    var joinedAt: Date

    @OptionalField(key: "left_at")
    var leftAt: Date?

    @Field(key: "left_early")
    var leftEarly: Bool

    @Field(key: "co_lock_ready")
    var coLockReady: Bool

    init() {
        // keep non-optional stored properties
        // safe if accessed before a row is loaded.
        self.joinedAt = Date()
        self.leftEarly = false
        self.coLockReady = false
    }

    init(id: UUID? = nil, userID: UUID, sessionID: UUID, config: String? = nil, coLockReady: Bool = false) {
        self.id = id
        self.userID = userID
        self.sessionID = sessionID
        self.config = config
        self.joinedAt = Date()
        self.leftEarly = false
        self.coLockReady = coLockReady
    }

    var participantStatus: ParticipantStatus {
        switch config {
        case Self.proximityExitConfig, Self.voluntaryExitConfig:
            return .left
        case Self.jailbreakConfig:
            return .jailbroken
        default:
            return .active
        }
    }
}
