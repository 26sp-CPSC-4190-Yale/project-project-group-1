//
//  CreateUserBlocks.swift
//  UnpluggedServer.Database.Migrations
//

import Fluent

struct CreateUserBlocks: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("user_blocks")
            .id()
            .field("blocker_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("blocked_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .unique(on: "blocker_id", "blocked_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("user_blocks").delete()
    }
}
