//
//  CreateSessions.swift (Creates rooms table)
//  UnpluggedServer.Database.Migrations
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent

struct CreateSessions: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("rooms")
            .id()
            .field("room_owner", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("start_time", .datetime, .required)
            .field("latitude", .double)
            .field("longitude", .double)
            .field("is_active", .bool, .required)
            .create()

    }

    func revert(on database: Database) async throws {
        try await database.schema("rooms").delete()
    }
}
