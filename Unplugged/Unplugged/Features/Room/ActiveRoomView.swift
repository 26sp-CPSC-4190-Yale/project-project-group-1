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
            }
            .navigationTitle(initialSession.session.title ?? "Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onClose()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Color.tertiaryColor)
                    }
                }
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
        .confirmationDialog("End Room?", isPresented: $viewModel.showEndConfirmation, titleVisibility: .visible) {
            Button("End for Everyone", role: .destructive) {
                Task { await viewModel.end(orchestrator: orchestrator) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will end the session for all participants.")
        }
    }

    @ViewBuilder
    private func content(phase: SessionOrchestrator.LifecyclePhase,
                         orchestrator: SessionOrchestrator) -> some View {
        switch phase {
        case .idle, .lobby:
            VStack(spacing: .spacingMd) {
                Image(systemName: "hourglass")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.tertiaryColor)
                Text("Waiting for the host to start")
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
            }
        case .locked:
            if let endsAt = orchestrator.countdownEndsAt {
                CountdownView(endsAt: endsAt)
            } else {
                ProgressView()
                    .tint(.tertiaryColor)
            }
        case .ended:
            VStack(spacing: .spacingMd) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)
                Text("Session Complete")
                    .font(.title2.bold())
                    .foregroundStyle(Color.tertiaryColor)
            }
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
            }
        }
    }

    @ViewBuilder
    private func footer(phase: SessionOrchestrator.LifecyclePhase,
                        isHost: Bool,
                        orchestrator: SessionOrchestrator) -> some View {
        if isHost {
            Group {
                switch phase {
                case .idle, .lobby:
                    Button {
                        Task { await viewModel.start(orchestrator: orchestrator) }
                    } label: {
                        Text("Lock Session")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.tertiaryColor)
                            .foregroundStyle(Color.primaryColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                case .locked:
                    Button(role: .destructive) {
                        viewModel.showEndConfirmation = true
                    } label: {
                        Text("End Session")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.destructiveColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                case .ended:
                    Button {
                        onClose()
                        dismiss()
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.tertiaryColor)
                            .foregroundStyle(Color.primaryColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, .spacingLg)
            .padding(.bottom, .spacingMd)
        }
    }
}
