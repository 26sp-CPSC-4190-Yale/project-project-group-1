import Fluent
import SQLKit

struct BackfillOAuthIdentities: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await sql.raw("""
        INSERT INTO oauth_identities (id, user_id, provider, subject, created_at)
        SELECT gen_random_uuid(), id, 'apple', apple_subject, NOW()
        FROM users
        WHERE apple_subject IS NOT NULL
        ON CONFLICT (user_id, provider) DO NOTHING
        """).run()

        try await sql.raw("""
        INSERT INTO oauth_identities (id, user_id, provider, subject, created_at)
        SELECT gen_random_uuid(), id, 'google', google_subject, NOW()
        FROM users
        WHERE google_subject IS NOT NULL
        ON CONFLICT (user_id, provider) DO NOTHING
        """).run()
    }

    // best-effort restore, this only runs while the apple_subject and google_subject columns still exist
    // (DropOAuthSubjectsFromUsers runs after this and reverts in reverse order)
    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await sql.raw("""
        UPDATE users
        SET apple_subject = oi.subject
        FROM oauth_identities oi
        WHERE users.id = oi.user_id AND oi.provider = 'apple'
        """).run()

        try await sql.raw("""
        UPDATE users
        SET google_subject = oi.subject
        FROM oauth_identities oi
        WHERE users.id = oi.user_id AND oi.provider = 'google'
        """).run()

        try await sql.raw("DELETE FROM oauth_identities").run()
    }
}
