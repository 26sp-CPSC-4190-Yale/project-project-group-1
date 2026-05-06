import Fluent
import SQLKit

struct CreateOAuthIdentities: AsyncMigration {
    func prepare(on database: Database) async throws {
        if let sql = database as? SQLDatabase {
            let exists = try await sql.raw("SELECT to_regclass('public.oauth_identities') AS reg").first()
            let alreadyExists = try exists?.decode(column: "reg", as: String?.self) != nil
            if !alreadyExists {
                try await database.schema("oauth_identities")
                    .id()
                    .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
                    .field("provider", .string, .required)
                    .field("subject", .string, .required)
                    .field("created_at", .datetime)
                    .unique(on: "user_id", "provider")
                    .unique(on: "provider", "subject")
                    .create()
            }
            try await sql.raw("ALTER TABLE oauth_identities DROP CONSTRAINT IF EXISTS oauth_identities_provider_valid").run()
            try await sql.raw("""
            ALTER TABLE oauth_identities
            ADD CONSTRAINT oauth_identities_provider_valid
            CHECK (provider IN ('apple', 'google'))
            """).run()
        }
    }

    func revert(on database: Database) async throws {
        try await database.schema("oauth_identities").delete()
    }
}
