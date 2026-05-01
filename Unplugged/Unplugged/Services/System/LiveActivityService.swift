import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class LiveActivityService {
    private static let proximityUpdateMinInterval: TimeInterval = 5
    private var lastProximityUpdate: [UUID: (date: Date, state: LockedSessionActivityAttributes.ProximityState)] = [:]

    func startOrUpdate(sessionID: UUID?, roomTitle: String?, endsAt: Date, showsProximity: Bool) async {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = AppLogger.measureMainThreadWork(
            "LiveActivityService.makeContentState",
            category: .ui,
            warnAfter: 0.02
        ) {
            LockedSessionActivityAttributes.ContentState(
                roomTitle: Self.normalizedTitle(roomTitle),
                endsAt: endsAt,
                showsProximity: showsProximity
            )
        }

        let existingActivity = AppLogger.measureMainThreadWork(
            "LiveActivityService.findExistingActivity",
            category: .ui,
            warnAfter: 0.02
        ) {
            preferredActivity(for: sessionID)
        }

        if let existing = existingActivity {
            // preserve any proximity state already pushed; only refresh title/endsAt here
            var merged = existing.content.state
            merged.roomTitle = state.roomTitle
            merged.endsAt = state.endsAt
            merged.showsProximity = state.showsProximity
            if !state.showsProximity {
                merged.proximity = .unknown
                merged.distanceMeters = nil
                merged.proximityObservedAt = nil
            }
            if existing.content.state == merged {
                return
            }
            await existing.update(ActivityContent(state: merged, staleDate: endsAt))
            return
        }

        let activities = AppLogger.measureMainThreadWork(
            "LiveActivityService.listActivitiesForReplacement",
            category: .ui,
            warnAfter: 0.02
        ) {
            Array(Activity<LockedSessionActivityAttributes>.activities)
        }

        for activity in activities {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }

        do {
            try AppLogger.measureMainThreadWork(
                "LiveActivityService.requestActivity",
                category: .ui,
                context: ["session": sessionID?.uuidString ?? "unknown"],
                warnAfter: 0.03
            ) {
                _ = try Activity.request(
                    attributes: LockedSessionActivityAttributes(sessionID: sessionID?.uuidString ?? "unknown"),
                    content: ActivityContent(state: state, staleDate: endsAt),
                    pushType: nil
                )
            }
        } catch {
            AppLogger.ui.warning(
                "Live Activity request failed",
                context: ["error": String(describing: error)]
            )
        }
        #endif
    }

    func updateProximity(
        sessionID: UUID,
        distanceMeters: Double?,
        state: LockedSessionActivityAttributes.ProximityState,
        observedAt: Date,
        roomTitle: String?,
        endsAt: Date
    ) async {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let existing = preferredActivity(for: sessionID) else { return }
        guard existing.content.state.showsProximity else { return }

        // throttle same-state updates so ActivityKit isn't pinged every 0.3s, but a state transition (in/out/lost) always goes through immediately
        if let last = lastProximityUpdate[sessionID],
           last.state == state,
           observedAt.timeIntervalSince(last.date) < Self.proximityUpdateMinInterval {
            return
        }

        var newState = existing.content.state
        newState.roomTitle = Self.normalizedTitle(roomTitle)
        newState.endsAt = endsAt
        newState.proximity = state
        newState.distanceMeters = distanceMeters
        newState.proximityObservedAt = observedAt

        lastProximityUpdate[sessionID] = (observedAt, state)

        if existing.content.state == newState {
            return
        }
        await existing.update(ActivityContent(state: newState, staleDate: endsAt))
        #endif
    }

    func end(sessionID: UUID?) async {
        #if canImport(ActivityKit)
        let activities = AppLogger.measureMainThreadWork(
            "LiveActivityService.listActivitiesForEnd",
            category: .ui,
            context: ["session": sessionID?.uuidString ?? "all"],
            warnAfter: 0.02
        ) {
            if let sessionID {
                return Activity<LockedSessionActivityAttributes>.activities.filter {
                    $0.attributes.sessionID == sessionID.uuidString
                }
            }
            return Array(Activity<LockedSessionActivityAttributes>.activities)
        }

        for activity in activities {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }

        if let sessionID {
            lastProximityUpdate.removeValue(forKey: sessionID)
        } else {
            lastProximityUpdate.removeAll()
        }
        #endif
    }

    func areActivitiesEnabled() -> Bool {
        #if canImport(ActivityKit)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    #if canImport(ActivityKit)
    private func preferredActivity(for sessionID: UUID?) -> Activity<LockedSessionActivityAttributes>? {
        let activities = Activity<LockedSessionActivityAttributes>.activities
        if let sessionID {
            return activities.first { $0.attributes.sessionID == sessionID.uuidString }
        }
        return activities.first
    }
    #endif

    private static func normalizedTitle(_ title: String?) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unplugged room" : trimmed
    }
}
