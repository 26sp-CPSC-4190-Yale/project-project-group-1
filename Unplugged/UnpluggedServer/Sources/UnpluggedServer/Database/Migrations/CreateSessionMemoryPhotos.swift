import Fluent

struct CreateSessionMemoryPhotos: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(SessionMemoryPhotoModel.schema)
            .id()
            .field("session_id", .uuid, .required, .references(RoomModel.schema, "id", onDelete: .cascade))
            .field("uploader_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("mime_type", .string, .required)
            .field("image_data", .data, .required)
            .field("thumbnail_data", .data)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(SessionMemoryPhotoModel.schema).delete()
    }
}

