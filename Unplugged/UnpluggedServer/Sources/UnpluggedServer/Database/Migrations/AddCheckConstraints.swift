import Fluent
import SQLKit

struct AddCheckConstraints: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await sql.raw("ALTER TABLE users DROP CONSTRAINT IF EXISTS users_points_non_negative").run()
        try await sql.raw("""
        ALTER TABLE users
        ADD CONSTRAINT users_points_non_negative
        CHECK (points >= 0)
        """).run()

        let roomsRow = try await sql.raw("SELECT to_regclass('public.rooms') AS reg").first()
        let roomsTable = try roomsRow?.decode(column: "reg", as: String?.self) != nil ? "rooms" : "sessions"
        let lockModeConstraint = roomsTable == "rooms" ? "rooms_lock_mode_valid" : "sessions_lock_mode_valid"
        if roomsTable == "rooms" {
            try await sql.raw("ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_lock_mode_valid").run()
            try await sql.raw("""
            ALTER TABLE rooms
            ADD CONSTRAINT rooms_lock_mode_valid
            CHECK (lock_mode IN ('standard', 'coLock'))
            """).run()
        } else {
            try await sql.raw("ALTER TABLE sessions DROP CONSTRAINT IF EXISTS \(unsafeRaw: lockModeConstraint)").run()
            try await sql.raw("""
            ALTER TABLE sessions
            ADD CONSTRAINT \(unsafeRaw: lockModeConstraint)
            CHECK (lock_mode IN ('standard', 'coLock'))
            """).run()
        }

        try await sql.raw("ALTER TABLE member_info DROP CONSTRAINT IF EXISTS member_info_config_valid").run()
        try await sql.raw("""
        ALTER TABLE member_info
        ADD CONSTRAINT member_info_config_valid
        CHECK (config IS NULL OR config IN ('proximity_exit', 'voluntary_exit', 'jailbreak'))
        """).run()

        try await sql.raw("ALTER TABLE friendships DROP CONSTRAINT IF EXISTS friendships_status_valid").run()
        try await sql.raw("""
        ALTER TABLE friendships
        ADD CONSTRAINT friendships_status_valid
        CHECK (status IN ('pending', 'accepted', 'blocked'))
        """).run()

        // co_lock_release_approvals intentionally allows requester_id == approver_id:
        // SessionController.requestCoLockRelease inserts the requester's own auto-approval
        // as (requester_id=X, approver_id=X). A <> constraint here would break that flow.
        try await sql.raw("ALTER TABLE co_lock_release_approvals DROP CONSTRAINT IF EXISTS co_lock_release_requester_not_approver").run()

        try await sql.raw("ALTER TABLE user_blocks DROP CONSTRAINT IF EXISTS user_blocks_blocker_not_blocked").run()
        try await sql.raw("""
        ALTER TABLE user_blocks
        ADD CONSTRAINT user_blocks_blocker_not_blocked
        CHECK (blocker_id <> blocked_id)
        """).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await sql.raw("ALTER TABLE user_blocks DROP CONSTRAINT IF EXISTS user_blocks_blocker_not_blocked").run()
        try await sql.raw("ALTER TABLE co_lock_release_approvals DROP CONSTRAINT IF EXISTS co_lock_release_requester_not_approver").run()
        try await sql.raw("ALTER TABLE friendships DROP CONSTRAINT IF EXISTS friendships_status_valid").run()
        try await sql.raw("ALTER TABLE member_info DROP CONSTRAINT IF EXISTS member_info_config_valid").run()
        try await sql.raw("ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_lock_mode_valid").run()
        try await sql.raw("ALTER TABLE users DROP CONSTRAINT IF EXISTS users_points_non_negative").run()
    }
}
