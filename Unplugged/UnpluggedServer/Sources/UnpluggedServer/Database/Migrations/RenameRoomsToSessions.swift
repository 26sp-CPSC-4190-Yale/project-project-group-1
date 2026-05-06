import Fluent
import SQLKit

struct RenameRoomsToSessions: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        if try await tableExists("rooms", on: sql) {
            try await sql.raw("ALTER TABLE rooms RENAME TO sessions").run()
        }
        if try await columnExists(table: "member_info", column: "room_id", on: sql) {
            try await sql.raw("ALTER TABLE member_info RENAME COLUMN room_id TO session_id").run()
        }
        if try await columnExists(table: "co_lock_release_approvals", column: "room_id", on: sql) {
            try await sql.raw("ALTER TABLE co_lock_release_approvals RENAME COLUMN room_id TO session_id").run()
        }

        try await sql.raw("ALTER INDEX IF EXISTS member_info_room_id_idx RENAME TO member_info_session_id_idx").run()
        try await sql.raw("ALTER INDEX IF EXISTS member_info_room_user_unique RENAME TO member_info_session_user_unique").run()
        try await sql.raw("ALTER INDEX IF EXISTS rooms_room_owner_idx RENAME TO sessions_room_owner_idx").run()
        try await sql.raw("ALTER INDEX IF EXISTS rooms_ended_at_idx RENAME TO sessions_ended_at_idx").run()
        try await sql.raw("ALTER INDEX IF EXISTS rooms_code_idx RENAME TO sessions_code_idx").run()

        if try await constraintExists("member_info_user_room_uq", on: sql) {
            try await sql.raw("ALTER TABLE member_info RENAME CONSTRAINT member_info_user_room_uq TO member_info_user_session_uq").run()
        }
        if try await constraintExists("rooms_lock_mode_valid", on: sql) {
            try await sql.raw("ALTER TABLE sessions RENAME CONSTRAINT rooms_lock_mode_valid TO sessions_lock_mode_valid").run()
        }
    }

    private func tableExists(_ name: String, on sql: SQLDatabase) async throws -> Bool {
        let row = try await sql.raw("SELECT to_regclass(\(bind: "public.\(name)")) AS reg").first()
        return try row?.decode(column: "reg", as: String?.self) != nil
    }

    private func columnExists(table: String, column: String, on sql: SQLDatabase) async throws -> Bool {
        let row = try await sql.raw("""
        SELECT 1 AS hit FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = \(bind: table) AND column_name = \(bind: column)
        LIMIT 1
        """).first()
        return row != nil
    }

    private func constraintExists(_ name: String, on sql: SQLDatabase) async throws -> Bool {
        let row = try await sql.raw("""
        SELECT 1 AS hit FROM pg_constraint WHERE conname = \(bind: name) LIMIT 1
        """).first()
        return row != nil
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await sql.raw("ALTER TABLE sessions RENAME CONSTRAINT sessions_lock_mode_valid TO rooms_lock_mode_valid").run()
        try await sql.raw("ALTER TABLE member_info RENAME CONSTRAINT member_info_user_session_uq TO member_info_user_room_uq").run()

        try await sql.raw("ALTER INDEX IF EXISTS sessions_code_idx RENAME TO rooms_code_idx").run()
        try await sql.raw("ALTER INDEX IF EXISTS sessions_ended_at_idx RENAME TO rooms_ended_at_idx").run()
        try await sql.raw("ALTER INDEX IF EXISTS sessions_room_owner_idx RENAME TO rooms_room_owner_idx").run()
        try await sql.raw("ALTER INDEX IF EXISTS member_info_session_user_unique RENAME TO member_info_room_user_unique").run()
        try await sql.raw("ALTER INDEX IF EXISTS member_info_session_id_idx RENAME TO member_info_room_id_idx").run()

        try await sql.raw("ALTER TABLE co_lock_release_approvals RENAME COLUMN session_id TO room_id").run()
        try await sql.raw("ALTER TABLE member_info RENAME COLUMN session_id TO room_id").run()
        try await sql.raw("ALTER TABLE sessions RENAME TO rooms").run()
    }
}
