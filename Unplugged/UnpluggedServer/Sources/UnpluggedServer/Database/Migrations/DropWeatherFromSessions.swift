import Fluent

struct DropWeatherFromSessions: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("rooms")
            .deleteField("weather_summary")
            .deleteField("weather_temperature_f")
            .deleteField("weather_symbol")
            .deleteField("weather_captured_at")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("rooms")
            .field("weather_summary", .string)
            .field("weather_temperature_f", .double)
            .field("weather_symbol", .string)
            .field("weather_captured_at", .datetime)
            .update()
    }
}
