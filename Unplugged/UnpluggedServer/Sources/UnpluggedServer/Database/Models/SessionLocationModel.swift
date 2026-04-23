import Fluent
import Vapor

final class SessionLocationModel: Model, @unchecked Sendable {
    static let schema = "session_locations"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "session_id")
    var sessionID: UUID

    @Field(key: "latitude")
    var latitude: Double

    @Field(key: "longitude")
    var longitude: Double

    @Field(key: "recorded_at")
    var recordedAt: Date

    init() {}

    init(id: UUID? = nil, sessionID: UUID, latitude: Double, longitude: Double) {
        self.id = id
        self.sessionID = sessionID
        self.latitude = latitude
        self.longitude = longitude
        self.recordedAt = Date()
    }
}
