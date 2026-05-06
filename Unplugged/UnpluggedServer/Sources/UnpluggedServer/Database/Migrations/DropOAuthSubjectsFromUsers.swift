import Fluent
import SQLKit

struct DropOAuthSubjectsFromUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("ALTER TABLE users DROP COLUMN IF EXISTS apple_subject").run()
        try await sql.raw("ALTER TABLE users DROP COLUMN IF EXISTS google_subject").run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            .field("apple_subject", .string)
            .field("google_subject", .string)
            .update()
    }
}
