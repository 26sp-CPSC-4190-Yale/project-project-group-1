import SwiftUI
import UnpluggedShared

struct SessionHistoryView: View {
    @Environment(DependencyContainer.self) private var deps
    @State private var viewModel = SessionHistoryViewModel()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.sessions.isEmpty {
                emptyState
            } else {
                ForEach(Array(viewModel.sessions.enumerated()), id: \.element.id) { index, session in
                    NavigationLink(value: session) {
                        row(for: session)
                    }
                    .buttonStyle(.plain)

                    if index < viewModel.sessions.count - 1 {
                        Divider()
                            .background(Color.tertiaryColor.opacity(0.1))
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .navigationDestination(for: SessionHistoryResponse.self) { session in
            SessionDetailView(session: session)
        }
        .task {
            await viewModel.load(sessions: deps.sessions, cache: deps.cache)
        }
    }

    private func row(for session: SessionHistoryResponse) -> some View {
        HStack(spacing: .spacingMd) {
            Image(systemName: iconName(for: session))
                .font(.system(size: 24))
                .foregroundColor(iconColor(for: session))

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title ?? "Unplugged Session")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.tertiaryColor)
                    .lineLimit(1)

                Text(subtitle(for: session))
                    .font(.captionFont)
                    .foregroundColor(.tertiaryColor.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(durationLabel(for: session))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tertiaryColor.opacity(0.7))
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.tertiaryColor.opacity(0.3))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, .spacingMd)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: .spacingSm) {
            Text(viewModel.isLoading ? "Loading…" : "No sessions yet")
                .font(.captionFont)
                .foregroundColor(.tertiaryColor.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacingLg)
    }

    private func iconName(for session: SessionHistoryResponse) -> String {
        session.leftEarly ? "xmark.circle.fill" : "checkmark.seal.fill"
    }

    private func iconColor(for session: SessionHistoryResponse) -> Color {
        session.leftEarly ? Color.destructiveColor.opacity(0.7) : Color.tertiaryColor.opacity(0.4)
    }

    private func subtitle(for session: SessionHistoryResponse) -> String {
        let date = dateLabel(for: session)
        if session.leftEarly {
            return "\(date) · Left early"
        }
        return date
    }

    private func dateLabel(for session: SessionHistoryResponse) -> String {
        if let ended = session.endedAt {
            return dateFormatter.string(from: ended)
        }
        if let started = session.startedAt {
            return dateFormatter.string(from: started)
        }
        return ""
    }

    private func durationLabel(for session: SessionHistoryResponse) -> String {
        if let actual = session.actualFocusedSeconds, actual > 0 {
            return TimeInterval(actual).humanReadable
        }
        if let planned = session.durationSeconds, planned > 0 {
            return TimeInterval(planned).humanReadable
        }
        return "—"
    }
}

#Preview {
    NavigationStack {
        SessionHistoryView()
            .padding()
            .background(Color.primaryColor)
            .environment(DependencyContainer())
    }
}
