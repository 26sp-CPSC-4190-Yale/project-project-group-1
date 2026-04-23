import Fluent
import SQLKit

struct AddRoomCodeToRooms: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("rooms")
            .field("code", .string)
            .update()

        guard let sql = database as? SQLDatabase else { return }

        try await sql.raw("""
        UPDATE rooms
        SET code = UPPER(SUBSTRING(REPLACE(id::text, '-', '') FROM 1 FOR 6))
        WHERE code IS NULL
        """).run()

        try await sql.raw("CREATE INDEX IF NOT EXISTS rooms_code_idx ON rooms (code)").run()
    }

    func revert(on database: Database) async throws {
        if let sql = database as? SQLDatabase {
            try await sql.raw("DROP INDEX IF EXISTS rooms_code_idx").run()
        }

        try await database.schema("rooms")
            .deleteField("code")
            .update()
    }
}
