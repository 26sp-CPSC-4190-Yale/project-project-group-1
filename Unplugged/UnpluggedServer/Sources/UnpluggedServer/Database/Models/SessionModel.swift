import Fluent
import Vapor

final class RoomModel: Model, @unchecked Sendable {
    static let schema = "rooms"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "room_owner")
    var roomOwner: UUID

    @Field(key: "start_time")
    var startTime: Date

    @OptionalField(key: "latitude")
    var latitude: Double?

    @OptionalField(key: "longitude")
    var longitude: Double?

    @Field(key: "is_active")
    var isActive: Bool

    @OptionalField(key: "code")
    var code: String?

    @OptionalField(key: "title")
    var title: String?

    @OptionalField(key: "duration_seconds")
    var durationSeconds: Int?

    @OptionalField(key: "locked_at")
    var lockedAt: Date?

    @OptionalField(key: "ends_at")
    var endsAt: Date?

    @OptionalField(key: "ended_at")
    var endedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        roomOwner: UUID,
        isActive: Bool = true,
        code: String? = nil,
        title: String? = nil,
        durationSeconds: Int? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.roomOwner = roomOwner
        self.startTime = Date()
        self.isActive = isActive
        self.code = code
        self.title = title
        self.durationSeconds = durationSeconds
        self.latitude = latitude
        self.longitude = longitude
    }
}
