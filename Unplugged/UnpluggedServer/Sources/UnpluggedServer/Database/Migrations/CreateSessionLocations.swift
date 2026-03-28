//
//  CreateSessionLocations.swift
//  UnpluggedServer.Database.Migrations
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

// Location data is now stored directly on the rooms table (optional latitude/longitude columns).
// Keeping this file for reference — uncomment if a separate locations table is needed later.

//import Fluent
//
//struct CreateSessionLocations: AsyncMigration {
//    func prepare(on database: Database) async throws {
//        try await database.schema("session_locations")
//            .id()
//            .field("session_id", .uuid, .required, .references("sessions", "id", onDelete: .cascade))
//            .field("latitude", .double, .required)
//            .field("longitude", .double, .required)
//            .field("recorded_at", .datetime, .required)
//            .create()
//    }
//
//    func revert(on database: Database) async throws {
//        try await database.schema("session_locations").delete()
//    }
//}
