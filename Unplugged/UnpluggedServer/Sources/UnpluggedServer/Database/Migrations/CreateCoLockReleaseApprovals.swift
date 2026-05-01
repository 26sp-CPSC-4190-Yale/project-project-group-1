import Fluent

struct CreateCoLockReleaseApprovals: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(CoLockReleaseApprovalModel.schema)
            .id()
            .field("room_id", .uuid, .required, .references(RoomModel.schema, "id", onDelete: .cascade))
            .field("requester_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("approver_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .unique(on: "room_id", "requester_id", "approver_id", name: "co_lock_release_unique")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(CoLockReleaseApprovalModel.schema).delete()
    }
}

