import SwiftUI
import UnpluggedShared

struct ActiveRoomView: View {
    let session: SessionResponse
    let sessions: SessionAPIService
    var onEnd: () -> Void

    @State private var viewModel: ActiveRoomViewModel
    @Environment(\.dismiss) private var dismiss

    init(session: SessionResponse, sessions: SessionAPIService, currentUserID: UUID, onEnd: @escaping () -> Void) {
        self.session = session
        self.sessions = sessions
        self.onEnd = onEnd
        _viewModel = State(initialValue: ActiveRoomViewModel(session: session, currentUserID: currentUserID))
    }

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            VStack(spacing: .spacingLg) {
                HStack {
                    Button(action: {
                        onEnd()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.tertiaryColor)
                    }
                    Spacer()
                    Text("Room")
                        .font(.headlineFont)
                        .foregroundColor(.tertiaryColor)
                    Spacer()
                    Image(systemName: "xmark")
                        .font(.system(size: 18))
                        .opacity(0)
                }
                .padding(.horizontal, .spacingLg)

                Spacer()

                Button(action: {}) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.tertiaryColor)
                }
                .buttonStyle(LiquidGlassButtonStyle(diameter: 180))

                Spacer()

                VStack(alignment: .leading, spacing: .spacingMd) {
                    Text("Members")
                        .font(.headlineFont)
                        .foregroundColor(.tertiaryColor)
                        .padding(.horizontal, .spacingLg)

                    List {
                        ForEach(viewModel.participants, id: \.id) { participant in
                            HStack(spacing: .spacingMd) {
                                ParticipantAvatar(name: participant.username, size: 40)

                                Text(participant.username)
                                    .font(.bodyFont)
                                    .foregroundColor(.tertiaryColor)

                                if participant.userID == viewModel.session.session.hostID {
                                    Text("Host")
                                        .font(.captionFont)
                                        .foregroundColor(.tertiaryColor.opacity(0.6))
                                }

                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await viewModel.refresh(sessions: sessions)
                    }
                }

                Spacer()

                if viewModel.isHost {
                    Button("End Room") {
                        viewModel.showEndConfirmation = true
                    }
                    .buttonStyle(DestructiveButtonStyle())
                    .padding(.horizontal, .spacingLg)
                    .padding(.bottom, .spacingMd)
                }
            }
        }
        .alert("End Room?", isPresented: $viewModel.showEndConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("End", role: .destructive) {
                onEnd()
                dismiss()
            }
        } message: {
            Text("This will end the session for everyone.")
        }
    }
}
