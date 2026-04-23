//
//  DropEndsAtFromRooms.swift
//  UnpluggedServer.Database.Migrations
//

import Fluent
import SQLKit

struct DropEndsAtFromRooms: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("rooms")
            .deleteField("ends_at")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("rooms")
            .field("ends_at", .datetime)
            .update()

        if let sql = database as? SQLDatabase {
            try await sql.raw("""
            UPDATE rooms
            SET ends_at = locked_at + (duration_seconds * INTERVAL '1 second')
            WHERE locked_at IS NOT NULL AND duration_seconds IS NOT NULL
            """).run()
        }
    }
}
