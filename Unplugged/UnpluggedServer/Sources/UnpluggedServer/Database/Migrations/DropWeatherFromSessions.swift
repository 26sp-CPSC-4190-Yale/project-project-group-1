import Fluent
import SQLKit

struct DropWeatherFromSessions: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        let roomsExists = try await sql.raw("SELECT to_regclass('public.rooms') AS reg").first()
        let target = try roomsExists?.decode(column: "reg", as: String?.self) != nil ? "rooms" : "sessions"
        if target == "rooms" {
            try await sql.raw("ALTER TABLE rooms DROP COLUMN IF EXISTS weather_summary").run()
            try await sql.raw("ALTER TABLE rooms DROP COLUMN IF EXISTS weather_temperature_f").run()
            try await sql.raw("ALTER TABLE rooms DROP COLUMN IF EXISTS weather_symbol").run()
            try await sql.raw("ALTER TABLE rooms DROP COLUMN IF EXISTS weather_captured_at").run()
        } else {
            try await sql.raw("ALTER TABLE sessions DROP COLUMN IF EXISTS weather_summary").run()
            try await sql.raw("ALTER TABLE sessions DROP COLUMN IF EXISTS weather_temperature_f").run()
            try await sql.raw("ALTER TABLE sessions DROP COLUMN IF EXISTS weather_symbol").run()
            try await sql.raw("ALTER TABLE sessions DROP COLUMN IF EXISTS weather_captured_at").run()
        }
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
