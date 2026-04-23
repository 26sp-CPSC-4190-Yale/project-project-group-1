import SwiftUI
import UnpluggedShared

struct SessionDetailView: View {
    let session: SessionHistoryResponse

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: .spacingLg) {
                    header

                    durationCard

                    outcomeCard

                    if session.participantCount > 1 {
                        metaRow(icon: "person.2.fill",
                                label: "Participants",
                                value: "\(session.participantCount)")
                    }

                    if let started = session.startedAt {
                        metaRow(icon: "play.circle.fill",
                                label: "Started",
                                value: Self.dateFormatter.string(from: started))
                    }

                    if let ended = session.endedAt {
                        metaRow(icon: "stop.circle.fill",
                                label: "Ended",
                                value: Self.dateFormatter.string(from: ended))
                    }

                    if let leftAt = session.leftAt {
                        metaRow(icon: "door.left.hand.open",
                                label: "You left",
                                value: Self.dateFormatter.string(from: leftAt))
                    }
                }
                .padding(.horizontal, .spacingLg)
                .padding(.vertical, .spacingMd)
            }
        }
        .navigationTitle(session.title ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title ?? "Unplugged Session")
                .font(.title2.bold())
                .foregroundStyle(Color.tertiaryColor)
            if let started = session.startedAt {
                Text(Self.dateFormatter.string(from: started))
                    .font(.subheadline)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
            }
        }
        .padding(.top, .spacingSm)
    }

    private var durationCard: some View {
        VStack(spacing: .spacingMd) {
            HStack(spacing: .spacingMd) {
                durationBlock(
                    title: "Planned",
                    seconds: session.durationSeconds ?? 0,
                    color: Color.tertiaryColor.opacity(0.7)
                )
                durationBlock(
                    title: "Actual",
                    seconds: session.actualFocusedSeconds ?? 0,
                    color: actualColor
                )
            }
        }
    }

    private var actualColor: Color {
        session.leftEarly ? Color.destructiveColor : Color.secondaryColor
    }

    private func durationBlock(title: String, seconds: Int, color: Color) -> some View {
        VStack(spacing: .spacingSm) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.tertiaryColor.opacity(0.6))
            Text(TimeInterval(seconds).humanReadable)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacingLg)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadius))
    }

    private var outcomeCard: some View {
        HStack(spacing: .spacingMd) {
            Image(systemName: outcomeIcon)
                .font(.title2)
                .foregroundStyle(outcomeColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(outcomeTitle)
                    .font(.headline)
                    .foregroundStyle(Color.tertiaryColor)
                Text(outcomeSubtitle)
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
            }
            Spacer()
        }
        .padding(.spacingMd)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadius))
    }

    private var outcomeIcon: String {
        if session.leftEarly { return "xmark.circle.fill" }
        return "checkmark.seal.fill"
    }

    private var outcomeColor: Color {
        session.leftEarly ? Color.destructiveColor : Color.secondaryColor
    }

    private var outcomeTitle: String {
        if !session.leftEarly { return "Completed" }
        switch session.leaveReason {
        case "left_due_to_proximity": return "Left early — too far"
        default:                       return "Left early"
        }
    }

    private var outcomeSubtitle: String {
        let planned = session.durationSeconds ?? 0
        let actual = session.actualFocusedSeconds ?? 0
        if !session.leftEarly {
            return "You stayed locked in the full \(TimeInterval(planned).humanReadable)."
        }
        let missed = max(0, planned - actual)
        return "You stayed \(TimeInterval(actual).humanReadable) of \(TimeInterval(planned).humanReadable) — \(TimeInterval(missed).humanReadable) short."
    }

    private func metaRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                .frame(width: 24)
            Text(label)
                .foregroundStyle(Color.tertiaryColor.opacity(0.6))
            Spacer()
            Text(value)
                .foregroundStyle(Color.tertiaryColor)
        }
        .font(.subheadline)
        .padding(.spacingMd)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadius))
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(session: SessionHistoryResponse(
            id: UUID(),
            title: "Study Session",
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date().addingTimeInterval(-300),
            durationSeconds: 3600,
            participantCount: 2,
            latitude: nil,
            longitude: nil,
            actualFocusedSeconds: 900,
            leftEarly: true,
            leftAt: Date().addingTimeInterval(-2700),
            leaveReason: "left_due_to_proximity"
        ))
    }
}
