//
//  CreateParticipants.swift (Creates member_info table)
//  UnpluggedServer.Database.Migrations
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent

struct CreateParticipants: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("member_info")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("room_id", .uuid, .required, .references("rooms", "id", onDelete: .cascade))
            .field("config", .string)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("member_info").delete()
    }
}
