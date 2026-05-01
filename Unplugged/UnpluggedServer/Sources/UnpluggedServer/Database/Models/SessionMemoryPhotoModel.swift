import Fluent
import Vapor

final class SessionMemoryPhotoModel: Model, @unchecked Sendable {
    static let schema = "session_memory_photos"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "session_id")
    var sessionID: UUID

    @Field(key: "uploader_id")
    var uploaderID: UUID

    @Field(key: "mime_type")
    var mimeType: String

    @Field(key: "image_data")
    var imageData: Data

    @OptionalField(key: "thumbnail_data")
    var thumbnailData: Data?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        sessionID: UUID,
        uploaderID: UUID,
        mimeType: String,
        imageData: Data,
        thumbnailData: Data? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.uploaderID = uploaderID
        self.mimeType = mimeType
        self.imageData = imageData
        self.thumbnailData = thumbnailData
    }
}

