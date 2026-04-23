import Fluent

struct AddJailbreakReason: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("jailbreaks")
            .field("reason", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("jailbreaks")
            .deleteField("reason")
            .update()
    }
}
