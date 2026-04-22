//
//  AddTimestampsToMembers.swift
//  UnpluggedServer.Database.Migrations
//

import Fluent

struct AddTimestampsToMembers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("member_info")
            .field("joined_at", .datetime, .required, .custom("DEFAULT NOW()"))
            .field("left_at", .datetime)
            .field("left_early", .bool, .required, .custom("DEFAULT FALSE"))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("member_info")
            .deleteField("joined_at")
            .deleteField("left_at")
            .deleteField("left_early")
            .update()
    }
}
