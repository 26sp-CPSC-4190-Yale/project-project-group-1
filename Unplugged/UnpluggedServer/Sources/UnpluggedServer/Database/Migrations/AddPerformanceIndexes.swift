//
//  AddPerformanceIndexes.swift
//  UnpluggedServer.Database.Migrations
//
//  Covers indexes the app actually queries on — without these the hot paths
//  (session history, friend graph, room membership, push token lookup) do
//  seq-scans that will degrade linearly with user count. Safe to run once;
//  `CREATE INDEX IF NOT EXISTS` keeps re-runs idempotent.
//

import Fluent
import SQLKit

struct AddPerformanceIndexes: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // member_info: looked up by user (session history) and by (room, user) (membership check).
        try await sql.raw("CREATE INDEX IF NOT EXISTS member_info_user_id_idx ON member_info (user_id)").run()
        try await sql.raw("CREATE INDEX IF NOT EXISTS member_info_room_id_idx ON member_info (room_id)").run()
        try await sql.raw("CREATE UNIQUE INDEX IF NOT EXISTS member_info_room_user_unique ON member_info (room_id, user_id)").run()

        // rooms: filtered by owner (profile) and by ended_at (history pagination).
        try await sql.raw("CREATE INDEX IF NOT EXISTS rooms_room_owner_idx ON rooms (room_owner)").run()
        try await sql.raw("CREATE INDEX IF NOT EXISTS rooms_ended_at_idx ON rooms (ended_at)").run()

        // friendships: graph lookups go through either side of the pair.
        try await sql.raw("CREATE INDEX IF NOT EXISTS friendships_user_1_idx ON friendships (user_1_id)").run()
        try await sql.raw("CREATE INDEX IF NOT EXISTS friendships_user_2_idx ON friendships (user_2_id)").run()

        // users.device_token: looked up on every push fan-out. Partial index keeps it
        // small (only users who have a token set).
        try await sql.raw("CREATE INDEX IF NOT EXISTS users_device_token_idx ON users (device_token) WHERE device_token IS NOT NULL").run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        for name in [
            "member_info_user_id_idx",
            "member_info_room_id_idx",
            "member_info_room_user_unique",
            "rooms_room_owner_idx",
            "rooms_ended_at_idx",
            "friendships_user_1_idx",
            "friendships_user_2_idx",
            "users_device_token_idx"
        ] {
            try await sql.raw("DROP INDEX IF EXISTS \(SQLRaw(name))").run()
        }
    }
}
