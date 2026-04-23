import Fluent

struct CreateFriendships: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("friendships")
            .id()
            .field("user_1_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("user_2_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("status", .string, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("friendships").delete()
    }
}
