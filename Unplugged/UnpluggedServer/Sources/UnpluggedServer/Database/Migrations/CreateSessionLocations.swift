// retained for reference, location now lives on the rooms table as optional lat/lng columns

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
