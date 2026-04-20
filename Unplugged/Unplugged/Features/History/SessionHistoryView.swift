//
//  SessionHistoryView.swift
//  Unplugged.Features.History
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

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
                    HStack(spacing: .spacingMd) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.tertiaryColor.opacity(0.4))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title ?? "Unplugged Session")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.tertiaryColor)
                                .lineLimit(1)

                            Text(dateLabel(for: session))
                                .font(.captionFont)
                                .foregroundColor(.tertiaryColor.opacity(0.4))
                        }

                        Spacer()

                        Text(durationLabel(for: session))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.tertiaryColor.opacity(0.7))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.tertiaryColor.opacity(0.3))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, .spacingMd)

                    if index < viewModel.sessions.count - 1 {
                        Divider()
                            .background(Color.tertiaryColor.opacity(0.1))
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .task {
            await viewModel.load(sessions: deps.sessions, cache: deps.cache)
        }
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
        guard let seconds = session.durationSeconds, seconds > 0 else { return "—" }
        return TimeInterval(seconds).humanReadable
    }
}

#Preview {
    SessionHistoryView()
        .padding()
        .background(Color.primaryColor)
        .environment(DependencyContainer())
}
