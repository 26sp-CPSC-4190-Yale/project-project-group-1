//
//  CreateJailbreaks.swift
//  UnpluggedServer.Database.Migrations
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent

struct CreateJailbreaks: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("jailbreaks")
            .id()
            .field("session_id", .uuid, .required, .references("rooms", "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("detected_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("jailbreaks").delete()
    }
}
