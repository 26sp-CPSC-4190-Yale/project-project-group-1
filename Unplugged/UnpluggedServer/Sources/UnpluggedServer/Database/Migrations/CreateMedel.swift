import Fluent

struct CreateMedal: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("medals")
            .id()
            .field("name", .string, .required)
            .field("description", .string, .required)
            .field("icon", .string, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("medals").delete()
    }
}