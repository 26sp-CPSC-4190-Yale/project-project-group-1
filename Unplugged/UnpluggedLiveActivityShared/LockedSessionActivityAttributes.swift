#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct LockedSessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var roomTitle: String
        var endsAt: Date
    }

    var sessionID: String
}
#endif
