import Fluent

struct AddDeletedAtToUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("deleted_at", .datetime)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            .deleteField("deleted_at")
            .update()
    }
}
