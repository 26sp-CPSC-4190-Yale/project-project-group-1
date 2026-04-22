//
//  CreateUserReports.swift
//  UnpluggedServer.Database.Migrations
//

import Fluent

struct CreateUserReports: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("user_reports")
            .id()
            .field("reporter_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("reported_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("reason", .string, .required)
            .field("details", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("user_reports").delete()
    }
}
