import SwiftUI
import UnpluggedShared

struct ActiveRoomView: View {
    let initialSession: SessionResponse
    let currentUserID: UUID
    var onClose: () -> Void

    @Environment(DependencyContainer.self) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ActiveRoomViewModel

    init(session: SessionResponse, currentUserID: UUID, onClose: @escaping () -> Void) {
        self.initialSession = session
        self.currentUserID = currentUserID
        self.onClose = onClose
        _viewModel = State(initialValue: ActiveRoomViewModel(currentUserID: currentUserID))
    }

    var body: some View {
        let orchestrator = deps.sessionOrchestrator
        let isHost = viewModel.isHost(orchestrator: orchestrator)
        let phase = orchestrator.phase

        return ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            VStack(spacing: .spacingLg) {
                header

                Spacer()

                content(phase: phase, orchestrator: orchestrator)

                Spacer()

                memberList(orchestrator: orchestrator)

                Spacer()

                footer(phase: phase, isHost: isHost, orchestrator: orchestrator)
            }
        }
        .task {
            await orchestrator.enterLobby(session: initialSession)
        }
        .onChange(of: orchestrator.phase) { _, newPhase in
            if newPhase == .ended {
                viewModel.showRecap = true
            }
        }
        .sheet(isPresented: $viewModel.showRecap) {
            if let id = orchestrator.currentSession?.session.id {
                RecapView(sessionID: id)
                    .environment(deps)
            }
        }
        .alert("End Room?", isPresented: $viewModel.showEndConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("End", role: .destructive) {
                Task { await viewModel.end(orchestrator: orchestrator) }
            }
        } message: {
            Text("This will end the session for everyone.")
        }
    }

    private var header: some View {
        HStack {
            Button(action: {
                onClose()
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.tertiaryColor)
            }
            Spacer()
            Text(initialSession.session.title ?? "Room")
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor)
            Spacer()
            Image(systemName: "xmark")
                .font(.system(size: 18))
                .opacity(0)
        }
        .padding(.horizontal, .spacingLg)
    }

    @ViewBuilder
    private func content(phase: SessionOrchestrator.LifecyclePhase,
                         orchestrator: SessionOrchestrator) -> some View {
        switch phase {
        case .idle, .lobby:
            VStack(spacing: .spacingMd) {
                Image(systemName: "hourglass")
                    .font(.system(size: 64))
                    .foregroundColor(.tertiaryColor)
                Text("Waiting for the host to lock")
                    .font(.bodyFont)
                    .foregroundColor(.tertiaryColor.opacity(0.7))
            }
        case .locked:
            if let endsAt = orchestrator.countdownEndsAt {
                CountdownView(endsAt: endsAt)
            } else {
                ProgressView()
            }
        case .ended:
            VStack(spacing: .spacingMd) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.tertiaryColor)
                Text("Session complete")
                    .font(.titleFont)
                    .foregroundColor(.tertiaryColor)
            }
        }
    }

    private func memberList(orchestrator: SessionOrchestrator) -> some View {
        VStack(alignment: .leading, spacing: .spacingMd) {
            Text("Members")
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor)
                .padding(.horizontal, .spacingLg)

            VStack(spacing: .spacingSm) {
                ForEach(orchestrator.participants, id: \.id) { participant in
                    HStack(spacing: .spacingMd) {
                        ParticipantAvatar(name: participant.username, size: 40)
                        Text(participant.username)
                            .font(.bodyFont)
                            .foregroundColor(.tertiaryColor)
                        if participant.isHost {
                            Text("Host")
                                .font(.captionFont)
                                .foregroundColor(.tertiaryColor.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, .spacingLg)
                    .padding(.vertical, .spacingSm)
                }
            }
        }
    }

    @ViewBuilder
    private func footer(phase: SessionOrchestrator.LifecyclePhase,
                        isHost: Bool,
                        orchestrator: SessionOrchestrator) -> some View {
        if isHost {
            switch phase {
            case .idle, .lobby:
                Button("Lock Session") {
                    Task { await viewModel.start(orchestrator: orchestrator) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, .spacingLg)
                .padding(.bottom, .spacingMd)
            case .locked:
                Button("End Session") {
                    viewModel.showEndConfirmation = true
                }
                .buttonStyle(DestructiveButtonStyle())
                .padding(.horizontal, .spacingLg)
                .padding(.bottom, .spacingMd)
            case .ended:
                Button("Close") {
                    onClose()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, .spacingLg)
                .padding(.bottom, .spacingMd)
            }
        }
    }
}
