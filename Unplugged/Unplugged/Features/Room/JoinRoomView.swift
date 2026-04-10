import SwiftUI
import UnpluggedShared

struct JoinRoomView: View {
    let sessions: SessionAPIService
    let touchTips: TouchTipsService
    var onJoinRoom: (SessionResponse) -> Void

    @State private var viewModel = JoinRoomViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: .spacingMd) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.tertiaryColor.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, .spacingSm)

            Text("Join Room")
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor)
                .padding(.top, .spacingSm)

            Spacer()

            VStack(spacing: .spacingMd) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 56))
                    .foregroundColor(.tertiaryColor)
                    .symbolEffect(.pulse, isActive: viewModel.isListening)

                Text(viewModel.hasFoundRoom ? "Connected to room!" : "Bring your phone close to the host")
                    .font(.bodyFont)
                    .foregroundColor(viewModel.hasFoundRoom ? .green : .tertiaryColor.opacity(0.7))

                if viewModel.isJoining {
                    ProgressView()
                        .tint(viewModel.hasFoundRoom ? .green : .tertiaryColor)
                }
            }

            Spacer()

            VStack(spacing: .spacingMd) {
                Text("Or enter room code")
                    .font(.captionFont)
                    .foregroundColor(.tertiaryColor.opacity(0.6))

                TextField("", text: $viewModel.manualCode, prompt: Text("Room code").foregroundColor(.tertiaryColor.opacity(0.4)))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.tertiaryColor)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.spacingMd)
                    .background(Color.surfaceColor)
                    .cornerRadius(.cornerRadiusSm)



                Button("Join") {
                    Task {
                        await viewModel.joinWithCode(sessions: sessions)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canJoinManually)
                .opacity(viewModel.canJoinManually ? 1 : 0.5)
            }
            .padding(.horizontal, .spacingLg)
            .padding(.bottom, .spacingMd)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primaryColor.opacity(0.85))
        .joinRoomAlert(viewModel: viewModel)
        .onAppear {
            viewModel.startListening(touchTips: touchTips, sessions: sessions)
        }
        .onDisappear {
            viewModel.stopListening(touchTips: touchTips)
        }
        .onChange(of: viewModel.joinedSession?.id) { _, id in
            if id != nil, let session = viewModel.joinedSession {
                onJoinRoom(session)
            }
        }
    }
}

extension JoinRoomView {
    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )
    }
}

extension View {
    func joinRoomAlert(viewModel: JoinRoomViewModel) -> some View {
        self.alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            ),
            actions: { Button("OK", role: .cancel) { viewModel.error = nil } },
            message: { Text(viewModel.error ?? "Something went wrong.") }
        )
    }
}
