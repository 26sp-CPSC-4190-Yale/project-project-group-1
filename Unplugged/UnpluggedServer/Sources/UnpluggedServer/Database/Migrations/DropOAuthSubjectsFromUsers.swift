import Fluent

struct DropOAuthSubjectsFromUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .deleteField("apple_subject")
            .deleteField("google_subject")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            .field("apple_subject", .string)
            .field("google_subject", .string)
            .update()
    }
}
