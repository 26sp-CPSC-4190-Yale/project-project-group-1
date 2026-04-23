import SwiftUI
import UIKit
import AudioToolbox
import UnpluggedShared

struct ActiveRoomView: View {
    let initialSession: SessionResponse
    let isHost: Bool
    var onClose: () -> Void

    @Environment(DependencyContainer.self) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ActiveRoomViewModel
    @State private var reportTarget: ParticipantResponse?
    @State private var moderationError: String?

    init(session: SessionResponse, isHost: Bool, onClose: @escaping () -> Void) {
        self.initialSession = session
        self.isHost = isHost
        self.onClose = onClose
        _viewModel = State(initialValue: ActiveRoomViewModel(isHost: isHost))
    }

    var body: some View {
        let orchestrator = deps.sessionOrchestrator
        let isHost = viewModel.isHost(orchestrator: orchestrator)
        let phase = orchestrator.phase

        return NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                VStack(spacing: .spacingLg) {
                    Spacer()

                    content(phase: phase, orchestrator: orchestrator)

                    Spacer()

                    memberList(orchestrator: orchestrator)

                    Spacer()

                    footer(phase: phase, isHost: isHost, orchestrator: orchestrator)
                }

                if let seconds = orchestrator.proximityWarningSecondsRemaining {
                    proximityWarningOverlay(secondsRemaining: seconds)
                }
            }
            .navigationTitle(initialSession.session.title ?? "Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if shouldShowCloseButton(phase: phase, isHost: isHost) {
                    ToolbarItem(placement: .cancellationAction) {
                        closeButton(phase: phase, isHost: isHost)
                    }
                }
            }
        }
        .task(id: initialSession.session.id) {
            // Host keeps the room advertisable during the lobby phase so late
            // joiners can still pair via proximity while watching the member
            // list fill up. Advertising stops when the host locks (below) or
            // the view is dismissed.
            await viewModel.startLobbyIfNeeded(
                session: initialSession,
                orchestrator: orchestrator,
                touchTips: deps.touchTips
            )
        }
        .onChange(of: orchestrator.phase) { _, newPhase in
            if newPhase == .ended {
                viewModel.showRecap = true
            }
        }
        .onChange(of: orchestrator.participants.count) { oldCount, newCount in
            guard newCount > oldCount else { return }
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        .onChange(of: orchestrator.didLeaveCurrentSessionForProximity) { _, didLeave in
            guard didLeave else { return }
            orchestrator.acknowledgeProximityExitDismissal()
            onClose()
            dismiss()
        }
        .onDisappear {
            if isHost && deps.sessionOrchestrator.phase != .locked {
                Task { await deps.touchTips.stop() }
            }
        }
        .sheet(isPresented: $viewModel.showRecap) {
            if let id = orchestrator.currentSession?.session.id {
                RecapView(sessionID: id)
                    .environment(deps)
            }
        }
        .alert("Error",
               isPresented: Binding(
                   get: { orchestrator.errorMessage != nil },
                   set: { if !$0 { orchestrator.errorMessage = nil } }
               )) {
            Button("OK") { orchestrator.errorMessage = nil }
        } message: {
            Text(orchestrator.errorMessage ?? "")
        }
        .confirmationDialog("End Room?", isPresented: $viewModel.showEndConfirmation, titleVisibility: .visible) {
            Button("End for Everyone", role: .destructive) {
                Task { await viewModel.end(orchestrator: orchestrator) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will end the session for all participants.")
        }
        .confirmationDialog("Close Room?", isPresented: $viewModel.showCloseConfirmation, titleVisibility: .visible) {
            Button("Close Room", role: .destructive) {
                Task {
                    await viewModel.end(orchestrator: orchestrator)
                    await orchestrator.teardown()
                    onClose()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will end the room for anyone who has joined.")
        }
        .confirmationDialog("Leave Room?", isPresented: $viewModel.showLeaveConfirmation, titleVisibility: .visible) {
            Button("Leave Room", role: .destructive) {
                Task {
                    await orchestrator.participantLeave()
                    onClose()
                    dismiss()
                }
            }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("Leaving unlocks your apps right away. The session will keep running for everyone else.")
        }
        .sheet(item: $reportTarget) { target in
            ReportUserSheet(username: target.username) { reason, details in
                let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
                do {
                    try await deps.user.reportUser(
                        id: target.userID,
                        reason: reason,
                        details: trimmed.isEmpty ? nil : trimmed
                    )
                } catch {
                    moderationError = "Could not submit report"
                }
            }
        }
        .alert("Error",
               isPresented: Binding(
                   get: { moderationError != nil },
                   set: { if !$0 { moderationError = nil } }
               )) {
            Button("OK") { moderationError = nil }
        } message: {
            Text(moderationError ?? "")
        }
    }

    private func shouldShowCloseButton(
        phase: SessionOrchestrator.LifecyclePhase,
        isHost: Bool
    ) -> Bool {
        guard phase != .ended else { return false }
        if isHost {
            return phase == .idle || phase == .lobby
        }
        return true
    }

    private func closeButton(
        phase: SessionOrchestrator.LifecyclePhase,
        isHost: Bool
    ) -> some View {
        Button {
            if isHost {
                viewModel.showCloseConfirmation = true
            } else if phase == .locked {
                viewModel.showLeaveConfirmation = true
            } else {
                onClose()
                dismiss()
            }
        } label: {
            Image(systemName: "xmark")
                .foregroundStyle(Color.tertiaryColor)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    private func proximityWarningOverlay(secondsRemaining: Int) -> some View {
        VStack {
            Spacer()
            VStack(spacing: .spacingSm) {
                Image(systemName: "figure.walk.motion")
                    .font(.title2)
                    .foregroundStyle(Color.destructiveColor)
                Text("You're leaving the session as you're too far away")
                    .font(.headline)
                    .foregroundStyle(Color.tertiaryColor)
                    .multilineTextAlignment(.center)
                Text("\(secondsRemaining)s")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.destructiveColor)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.spacingLg)
            .background(Color.surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, .spacingLg)
            .padding(.bottom, .spacingXl)
        }
        .background(Color.black.opacity(0.35).ignoresSafeArea())
    }

    private func blockParticipant(_ participant: ParticipantResponse) async {
        do {
            try await deps.user.blockUser(id: participant.userID)
        } catch {
            moderationError = "Could not block user"
        }
    }

    @ViewBuilder
    private func content(phase: SessionOrchestrator.LifecyclePhase,
                         orchestrator: SessionOrchestrator) -> some View {
        switch phase {
        case .idle, .lobby:
            lobbyContent
        case .locked:
            if let endsAt = orchestrator.countdownEndsAt {
                CountdownView(endsAt: endsAt)
            } else {
                ProgressView()
                    .tint(.tertiaryColor)
            }
        case .ended:
            VStack(spacing: .spacingMd) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.tertiaryColor)
                Text("Session Ended")
                    .font(.title2.bold())
                    .foregroundStyle(Color.tertiaryColor)
            }
        }
    }

    // Unified lobby shown to both host and guest. The only visual difference
    // is the copy under the icon and the advertising pulse on the host side
    // — the room code is shown to everyone so joiners can confirm they're in
    // the right room and hosts can share it out-of-band.
    private var lobbyContent: some View {
        VStack(spacing: .spacingLg) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(Color.tertiaryColor)
                .symbolEffect(.pulse, isActive: isHost)

            Text(isHost
                 ? "Bring phones together to invite"
                 : "Waiting for the host to start")
                .font(.body)
                .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                Text("Room Code")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))

                Text(initialSession.session.code.uppercased())
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.tertiaryColor)
                    .kerning(4)
            }
            .padding(.spacingLg)
            .frame(maxWidth: .infinity)
            .background(Color.surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, .spacingLg)
        }
    }

    private func memberList(orchestrator: SessionOrchestrator) -> some View {
        VStack(alignment: .leading, spacing: .spacingSm) {
            Text("Members")
                .font(.headline)
                .foregroundStyle(Color.tertiaryColor)
                .padding(.horizontal, .spacingLg)

            ForEach(orchestrator.participants, id: \.id) { participant in
                HStack(spacing: .spacingMd) {
                    ParticipantAvatar(name: participant.username, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(participant.username)
                            .font(.body)
                            .foregroundStyle(Color.tertiaryColor)
                        if participant.isHost {
                            Text("Host")
                                .font(.caption)
                                .foregroundStyle(Color.tertiaryColor.opacity(0.5))
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, .spacingLg)
                .padding(.vertical, 6)
                .contextMenu {
                    if participant.userID != deps.cache.readUser()?.id {
                        Button {
                            reportTarget = participant
                        } label: {
                            Label("Report", systemImage: "flag")
                        }
                        Button(role: .destructive) {
                            Task { await blockParticipant(participant) }
                        } label: {
                            Label("Block", systemImage: "hand.raised")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func footer(phase: SessionOrchestrator.LifecyclePhase,
                        isHost: Bool,
                        orchestrator: SessionOrchestrator) -> some View {
        Group {
            if phase == .ended {
                Button {
                    onClose()
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if isHost {
                switch phase {
                case .idle, .lobby:
                    Button {
                        Task { await viewModel.start(orchestrator: orchestrator) }
                    } label: {
                        Text("Lock Session")
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PrimaryButtonStyle())
                case .locked:
                    Button(role: .destructive) {
                        viewModel.showEndConfirmation = true
                    } label: {
                        Text("End Session")
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DestructiveButtonStyle())
                case .ended:
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, .spacingLg)
        .padding(.bottom, .spacingMd)
    }
}
