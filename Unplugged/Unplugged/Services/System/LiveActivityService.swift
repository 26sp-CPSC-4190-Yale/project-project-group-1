import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class LiveActivityService {
    func startOrUpdate(sessionID: UUID?, roomTitle: String?, endsAt: Date) async {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = AppLogger.measureMainThreadWork(
            "LiveActivityService.makeContentState",
            category: .ui,
            warnAfter: 0.02
        ) {
            LockedSessionActivityAttributes.ContentState(
                roomTitle: Self.normalizedTitle(roomTitle),
                endsAt: endsAt
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
            if existing.content.state == state {
                return
            }
            await existing.update(ActivityContent(state: state, staleDate: endsAt))
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
