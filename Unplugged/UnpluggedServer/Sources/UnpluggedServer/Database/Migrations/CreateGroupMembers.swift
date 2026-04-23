import Fluent

struct CreateGroupMembers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("group_members")
            .id()
            .field("group_id", .uuid, .required, .references("groups", "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("joined_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("group_members").delete()
    }
}
