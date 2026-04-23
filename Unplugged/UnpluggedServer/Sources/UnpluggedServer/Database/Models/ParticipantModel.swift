import Fluent
import UnpluggedShared
import Vapor

final class MemberModel: Model, @unchecked Sendable {
    static let schema = "member_info"
    static let proximityExitConfig = "proximity_exit"
    static let voluntaryExitConfig = "voluntary_exit"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userID: UUID

    @Field(key: "room_id")
    var roomID: UUID

    @OptionalField(key: "config")
    var config: String?

    @Field(key: "joined_at")
    var joinedAt: Date

    @OptionalField(key: "left_at")
    var leftAt: Date?

    @Field(key: "left_early")
    var leftEarly: Bool

    init() {
        // keep non-optional stored properties
        // safe if accessed before a row is loaded.
        self.joinedAt = Date()
        self.leftEarly = false
    }

    init(id: UUID? = nil, userID: UUID, roomID: UUID, config: String? = nil) {
        self.id = id
        self.userID = userID
        self.roomID = roomID
        self.config = config
        self.joinedAt = Date()
        self.leftEarly = false
    }

    var participantStatus: ParticipantStatus {
        switch config {
        case Self.proximityExitConfig, Self.voluntaryExitConfig:
            return .left
        default:
            return .active
        }
    }
}
