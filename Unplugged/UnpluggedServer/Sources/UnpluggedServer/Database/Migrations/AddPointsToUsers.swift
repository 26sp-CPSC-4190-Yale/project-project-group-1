import Fluent

struct AddPointsToUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("points", .int, .required, .custom("DEFAULT 0"))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            .deleteField("points")
            .update()
    }
}
