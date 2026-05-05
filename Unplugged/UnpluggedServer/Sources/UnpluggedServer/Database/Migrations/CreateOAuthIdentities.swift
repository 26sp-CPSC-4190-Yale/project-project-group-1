import Fluent
import SQLKit

struct CreateOAuthIdentities: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("oauth_identities")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("provider", .string, .required)
            .field("subject", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "user_id", "provider")
            .unique(on: "provider", "subject")
            .create()

        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
        ALTER TABLE oauth_identities
        ADD CONSTRAINT oauth_identities_provider_valid
        CHECK (provider IN ('apple', 'google'))
        """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("oauth_identities").delete()
    }
}
