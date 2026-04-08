import Fluent

struct CreateUserMedalPivot: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("user_medal_pivot")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("medal_id", .uuid, .required, .references("medals", "id", onDelete: .cascade))
            .field("earned_at", .datetime)
            .unique(on: "user_id", "medal_id") // prevents duplicate medals per user
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("user_medal_pivot").delete()
    }
}