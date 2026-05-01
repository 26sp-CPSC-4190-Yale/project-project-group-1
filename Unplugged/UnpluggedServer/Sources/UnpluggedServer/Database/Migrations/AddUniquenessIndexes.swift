import Fluent
import SQLKit

struct AddUniquenessIndexes: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await sql.raw("""
        CREATE UNIQUE INDEX IF NOT EXISTS users_username_lower_unique
        ON users (LOWER(username))
        WHERE deleted_at IS NULL
        """).run()

        try await sql.raw("""
        CREATE UNIQUE INDEX IF NOT EXISTS friendships_pair_unique
        ON friendships (
            CASE WHEN user_1_id < user_2_id THEN user_1_id ELSE user_2_id END,
            CASE WHEN user_1_id < user_2_id THEN user_2_id ELSE user_1_id END
        )
        """).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("DROP INDEX IF EXISTS users_username_lower_unique").run()
        try await sql.raw("DROP INDEX IF EXISTS friendships_pair_unique").run()
    }
}

