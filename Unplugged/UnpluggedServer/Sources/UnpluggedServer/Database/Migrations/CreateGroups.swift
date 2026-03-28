//
//  CreateGroups.swift
//  UnpluggedServer.Database.Migrations
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent

struct CreateGroups: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("groups")
            .id()
            .field("name", .string, .required)
            .field("owner_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("groups").delete()
    }
}
