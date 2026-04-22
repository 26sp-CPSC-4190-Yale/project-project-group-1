//
//  AddEndedAtToRooms.swift
//  UnpluggedServer.Database.Migrations
//

import Fluent

struct AddEndedAtToRooms: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("rooms")
            .field("ended_at", .datetime)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("rooms")
            .deleteField("ended_at")
            .update()
    }
}
