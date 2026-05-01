import ActivityKit
import SwiftUI
import WidgetKit

struct LockedSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LockedSessionActivityAttributes.self) { context in
            LockedSessionLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.03, green: 0.16, blue: 0.33))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Locked", systemImage: "lock.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    LockDeadlineSummary(state: context.state, compact: true)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.showsProximity {
                        HStack(spacing: 12) {
                            ProximityBadge(
                                state: context.state.proximity,
                                distanceMeters: context.state.distanceMeters,
                                compact: false
                            )
                            Spacer(minLength: 8)
                            LockTimerText(state: context.state, font: .title3.weight(.bold))
                        }
                    } else {
                        LockTimerText(state: context.state, font: .title3.weight(.bold))
                    }
                }
            } compactLeading: {
                if context.state.showsProximity {
                    ProximityDot(state: context.state.proximity)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.white)
                }
            } compactTrailing: {
                LockTimerText(state: context.state, font: .caption2.weight(.semibold))
            } minimal: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.white)
            }
            .keylineTint(.white)
        }
    }
}

private struct LockedSessionLockScreenView: View {
    let context: ActivityViewContext<LockedSessionActivityAttributes>

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.14, blue: 0.30),
                            Color(red: 0.00, green: 0.27, blue: 0.47),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Locked", systemImage: "lock.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(context.state.roomTitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    LockDeadlineSummary(state: context.state, compact: false)
                }

                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    LockTimerText(
                        state: context.state,
                        font: .system(size: 30, weight: .bold, design: .rounded)
                    )
                    Text(context.state.isUnlimited ? "locked in" : "remaining")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.68))
                }

                if context.state.showsProximity {
                    ProximityBadge(
                        state: context.state.proximity,
                        distanceMeters: context.state.distanceMeters,
                        compact: false
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }
}

private struct LockDeadlineSummary: View {
    let state: LockedSessionActivityAttributes.ContentState
    let compact: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: compact ? 2 : 4) {
            Text(state.isUnlimited ? "Mode" : "Until")
                .font((compact ? Font.caption2 : Font.caption).weight(.medium))
                .foregroundStyle(.white.opacity(compact ? 0.72 : 0.68))
            if state.isUnlimited {
                Image(systemName: "infinity")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            } else {
                Text(state.endsAt, format: .dateTime.hour().minute())
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct LockTimerText: View {
    let state: LockedSessionActivityAttributes.ContentState
    let font: Font

    var body: some View {
        Text(timerInterval: timerInterval, countsDown: !state.isUnlimited)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(.white)
    }

    private var timerInterval: ClosedRange<Date> {
        if state.isUnlimited {
            return (state.lockedAt ?? Date())...Date.distantFuture
        }
        return Date()...state.endsAt
    }
}

private struct ProximityBadge: View {
    let state: LockedSessionActivityAttributes.ProximityState
    let distanceMeters: Double?
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            ProximityDot(state: state)
            VStack(alignment: .leading, spacing: 1) {
                Text(distanceText)
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if !compact {
                    Text(statusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var distanceText: String {
        guard let meters = distanceMeters else { return "—" }
        let feet = Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: .feet)
            .value
        return String(format: "%.1f ft", feet)
    }

    private var statusText: String {
        switch state {
        case .inRange: return "Together"
        case .outOfRange: return "Out of range"
        case .signalLost: return "Reconnecting"
        case .unknown: return "Connecting"
        }
    }
}

private struct ProximityDot: View {
    let state: LockedSessionActivityAttributes.ProximityState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 0.5)
            )
    }

    private var color: Color {
        switch state {
        case .inRange: return .green
        case .outOfRange: return .red
        case .signalLost: return .orange
        case .unknown: return .gray
        }
    }
}
