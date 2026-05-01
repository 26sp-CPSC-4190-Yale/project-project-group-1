import Fluent
import UnpluggedShared
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

    @OptionalField(key: "code")
    var code: String?

    @OptionalField(key: "title")
    var title: String?

    @OptionalField(key: "description")
    var description: String?

    @OptionalField(key: "duration_seconds")
    var durationSeconds: Int?

    @OptionalField(key: "lock_mode")
    var lockModeRaw: String?

    @OptionalField(key: "weather_summary")
    var weatherSummary: String?

    @OptionalField(key: "weather_temperature_f")
    var weatherTemperatureF: Double?

    @OptionalField(key: "weather_symbol")
    var weatherSymbol: String?

    @OptionalField(key: "weather_captured_at")
    var weatherCapturedAt: Date?

    @OptionalField(key: "locked_at")
    var lockedAt: Date?

    @OptionalField(key: "ended_at")
    var endedAt: Date?

    var endsAt: Date? {
        guard let lockedAt, let durationSeconds else { return nil }
        return lockedAt.addingTimeInterval(TimeInterval(durationSeconds))
    }

    var lockMode: SessionLockMode {
        get { SessionLockMode(rawValue: lockModeRaw ?? "") ?? .standard }
        set { lockModeRaw = newValue.rawValue }
    }

    init() {}

    init(
        id: UUID? = nil,
        roomOwner: UUID,
        code: String? = nil,
        title: String? = nil,
        description: String? = nil,
        durationSeconds: Int? = nil,
        lockMode: SessionLockMode = .standard,
        latitude: Double? = nil,
        longitude: Double? = nil,
        weather: SessionWeatherSnapshot? = nil
    ) {
        self.id = id
        self.roomOwner = roomOwner
        self.startTime = Date()
        self.code = code
        self.title = title
        self.description = description
        self.durationSeconds = durationSeconds
        self.lockModeRaw = lockMode.rawValue
        self.latitude = latitude
        self.longitude = longitude
        self.weatherSummary = weather?.summary
        self.weatherTemperatureF = weather?.temperatureFahrenheit
        self.weatherSymbol = weather?.conditionSymbol
        self.weatherCapturedAt = weather?.capturedAt
    }
}
