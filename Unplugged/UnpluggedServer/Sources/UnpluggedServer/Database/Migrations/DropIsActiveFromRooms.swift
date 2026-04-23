//
//  DropIsActiveFromRooms.swift
//  UnpluggedServer.Database.Migrations
//

import Fluent
import SQLKit

struct DropIsActiveFromRooms: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("rooms")
            .deleteField("is_active")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("rooms")
            .field("is_active", .bool)
            .update()

        if let sql = database as? SQLDatabase {
            try await sql.raw("UPDATE rooms SET is_active = (ended_at IS NULL)").run()
        }
    }
}
