import Fluent
import Vapor

final class CoLockReleaseApprovalModel: Model, @unchecked Sendable {
    static let schema = "co_lock_release_approvals"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "room_id")
    var roomID: UUID

    @Field(key: "requester_id")
    var requesterID: UUID

    @Field(key: "approver_id")
    var approverID: UUID

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, roomID: UUID, requesterID: UUID, approverID: UUID) {
        self.id = id
        self.roomID = roomID
        self.requesterID = requesterID
        self.approverID = approverID
    }
}

