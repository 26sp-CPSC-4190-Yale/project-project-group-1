import Fluent

struct AddPresenceExpiryToUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(UserModel.schema)
            .field("presence_expires_at", .datetime)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(UserModel.schema)
            .deleteField("presence_expires_at")
            .update()
    }
}
