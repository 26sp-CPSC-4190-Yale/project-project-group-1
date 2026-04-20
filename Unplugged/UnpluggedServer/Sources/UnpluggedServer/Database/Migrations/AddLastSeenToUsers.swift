//
//  AddLastSeenToUsers.swift
//  UnpluggedServer.Database.Migrations
//

import Fluent

struct AddLastSeenToUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("last_seen_at", .datetime)
            .field("apple_subject", .string)
            .field("google_subject", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            .deleteField("last_seen_at")
            .deleteField("apple_subject")
            .deleteField("google_subject")
            .update()
    }
}
