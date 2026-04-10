//
//  RecapView.swift
//  Unplugged.Features.Recap
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI
import UnpluggedShared

struct RecapView: View {
    let sessionID: UUID
    @Environment(DependencyContainer.self) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = RecapViewModel()

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: .spacingLg) {
                    header

                    if let recap = viewModel.recap {
                        stats(for: recap)
                        participants(for: recap)
                        if !recap.jailbreaks.isEmpty {
                            jailbreaks(for: recap)
                        }
                    } else if viewModel.isLoading {
                        ProgressView()
                            .padding(.top, .spacingXl)
                    } else if let error = viewModel.error {
                        Text(error)
                            .font(.bodyFont)
                            .foregroundColor(.tertiaryColor.opacity(0.7))
                            .padding(.top, .spacingXl)
                    }
                }
                .padding(.horizontal, .spacingLg)
                .padding(.vertical, .spacingLg)
            }
        }
        .task { await viewModel.load(sessionID: sessionID, service: deps.recap) }
    }

    private var header: some View {
        VStack(spacing: .spacingSm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.tertiaryColor)
            Text("Session Complete")
                .font(.titleFont)
                .foregroundColor(.tertiaryColor)
            if let title = viewModel.recap?.title {
                Text(title)
                    .font(.bodyFont)
                    .foregroundColor(.tertiaryColor.opacity(0.7))
            }
        }
        .padding(.top, .spacingXl)
    }

    private func stats(for recap: SessionRecapResponse) -> some View {
        HStack(spacing: .spacingMd) {
            StatBadge(
                value: TimeInterval(recap.durationSeconds).humanReadable,
                label: "Duration",
                valueSize: 22
            )
            StatBadge(
                value: "\(recap.participants.count)",
                label: "Members",
                valueSize: 22
            )
            StatBadge(
                value: "\(Int(recap.completionRate * 100))%",
                label: "Completion",
                valueSize: 22
            )
        }
    }

    private func participants(for recap: SessionRecapResponse) -> some View {
        VStack(alignment: .leading, spacing: .spacingSm) {
            Text("Who was here")
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor)

            ForEach(recap.participants) { participant in
                HStack(spacing: .spacingMd) {
                    ParticipantAvatar(name: participant.username, size: 40)
                    Text(participant.username)
                        .font(.bodyFont)
                        .foregroundColor(.tertiaryColor)
                    Spacer()
                    if participant.isHost {
                        Text("Host")
                            .font(.captionFont)
                            .foregroundColor(.tertiaryColor.opacity(0.6))
                    }
                }
                .padding(.spacingMd)
                .background(Color.surfaceColor)
                .cornerRadius(.cornerRadiusSm)
            }
        }
    }

    private func jailbreaks(for recap: SessionRecapResponse) -> some View {
        VStack(alignment: .leading, spacing: .spacingSm) {
            Text("Breaks from focus")
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor)

            ForEach(recap.jailbreaks) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.username)
                        .font(.bodyFont)
                        .foregroundColor(.tertiaryColor)
                    if let reason = entry.reason {
                        Text(reason)
                            .font(.captionFont)
                            .foregroundColor(.tertiaryColor.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.spacingMd)
                .background(Color.surfaceColor)
                .cornerRadius(.cornerRadiusSm)
            }
        }
    }
}
