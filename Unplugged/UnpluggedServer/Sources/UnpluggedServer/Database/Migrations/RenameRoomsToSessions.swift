import Fluent
import SQLKit

struct RenameRoomsToSessions: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await sql.raw("ALTER TABLE rooms RENAME TO sessions").run()
        try await sql.raw("ALTER TABLE member_info RENAME COLUMN room_id TO session_id").run()
        try await sql.raw("ALTER TABLE co_lock_release_approvals RENAME COLUMN room_id TO session_id").run()

        try await sql.raw("ALTER INDEX IF EXISTS member_info_room_id_idx RENAME TO member_info_session_id_idx").run()
        try await sql.raw("ALTER INDEX IF EXISTS member_info_room_user_unique RENAME TO member_info_session_user_unique").run()
        try await sql.raw("ALTER INDEX IF EXISTS rooms_room_owner_idx RENAME TO sessions_room_owner_idx").run()
        try await sql.raw("ALTER INDEX IF EXISTS rooms_ended_at_idx RENAME TO sessions_ended_at_idx").run()
        try await sql.raw("ALTER INDEX IF EXISTS rooms_code_idx RENAME TO sessions_code_idx").run()

        try await sql.raw("ALTER TABLE member_info RENAME CONSTRAINT member_info_user_room_uq TO member_info_user_session_uq").run()
        try await sql.raw("ALTER TABLE sessions RENAME CONSTRAINT rooms_lock_mode_valid TO sessions_lock_mode_valid").run()
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
