//
//  AddTimestampsToMembers.swift
//  UnpluggedServer.Database.Migrations
//

import Fluent
import SQLKit

struct AddTimestampsToMembers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("member_info")
            .field("joined_at", .datetime, .required, .custom("DEFAULT NOW()"))
            .field("left_at", .datetime)
            .field("left_early", .bool, .required, .custom("DEFAULT FALSE"))
            .unique(on: "user_id", "room_id", name: "member_info_user_room_uq")
            .update()

        // Backfill joined_at from rooms.start_time so historical rows reflect
        // when the user actually joined, not when this migration ran.
        if let sql = database as? SQLDatabase {
            try await sql.raw("""
                UPDATE member_info
                SET joined_at = rooms.start_time
                FROM rooms
                WHERE member_info.room_id = rooms.id
            """).run()
        }
    }

    func revert(on database: Database) async throws {
        try await database.schema("member_info")
            .deleteConstraint(name: "member_info_user_room_uq")
            .deleteField("joined_at")
            .deleteField("left_at")
            .deleteField("left_early")
            .update()
    }
}
