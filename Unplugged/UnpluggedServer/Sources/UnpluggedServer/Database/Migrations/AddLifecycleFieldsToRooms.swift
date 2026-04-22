//
//  AddLifecycleFieldsToRooms.swift
//  UnpluggedServer.Database.Migrations
//

import Fluent

struct AddLifecycleFieldsToRooms: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("rooms")
            .field("title", .string)
            .field("duration_seconds", .int)
            .field("locked_at", .datetime)
            .field("ends_at", .datetime)
            .field("ended_at", .datetime)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("rooms")
            .deleteField("title")
            .deleteField("duration_seconds")
            .deleteField("locked_at")
            .deleteField("ends_at")
            .deleteField("ended_at")
            .update()
    }
}
