import Fluent

struct AddSessionMetadataAndCoLock: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("rooms")
            .field("description", .string)
            .field("lock_mode", .string, .required, .custom("DEFAULT 'standard'"))
            .field("weather_summary", .string)
            .field("weather_temperature_f", .double)
            .field("weather_symbol", .string)
            .field("weather_captured_at", .datetime)
            .update()

        try await database.schema(MemberModel.schema)
            .field("co_lock_ready", .bool, .required, .custom("DEFAULT FALSE"))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(MemberModel.schema)
            .deleteField("co_lock_ready")
            .update()

        try await database.schema("rooms")
            .deleteField("description")
            .deleteField("lock_mode")
            .deleteField("weather_summary")
            .deleteField("weather_temperature_f")
            .deleteField("weather_symbol")
            .deleteField("weather_captured_at")
            .update()
    }
}

