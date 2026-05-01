#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct LockedSessionActivityAttributes: ActivityAttributes {
    enum ProximityState: String, Codable, Hashable {
        case unknown
        case inRange
        case outOfRange
        case signalLost
    }

    struct ContentState: Codable, Hashable {
        var roomTitle: String
        var endsAt: Date
        var showsProximity: Bool = true
        var proximity: ProximityState = .unknown
        var distanceMeters: Double? = nil
        var proximityObservedAt: Date? = nil
    }

    var sessionID: String
}
#endif
