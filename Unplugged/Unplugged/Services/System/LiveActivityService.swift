import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class LiveActivityService {
    func startOrUpdate(sessionID: UUID?, roomTitle: String?, endsAt: Date) async {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = LockedSessionActivityAttributes.ContentState(
            roomTitle: Self.normalizedTitle(roomTitle),
            endsAt: endsAt
        )

        if let existing = preferredActivity(for: sessionID) {
            if existing.content.state == state {
                return
            }
            await existing.update(ActivityContent(state: state, staleDate: endsAt))
            return
        }

        for activity in Activity<LockedSessionActivityAttributes>.activities {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }

        do {
            _ = try Activity.request(
                attributes: LockedSessionActivityAttributes(sessionID: sessionID?.uuidString ?? "unknown"),
                content: ActivityContent(state: state, staleDate: endsAt),
                pushType: nil
            )
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
        let activities: [Activity<LockedSessionActivityAttributes>]
        if let sessionID {
            activities = Activity<LockedSessionActivityAttributes>.activities.filter {
                $0.attributes.sessionID == sessionID.uuidString
            }
        } else {
            activities = Array(Activity<LockedSessionActivityAttributes>.activities)
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
