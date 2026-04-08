import SwiftUI
import UnpluggedShared

struct JoinRoomView: View {
    let sessions: SessionAPIService
    let touchTips: TouchTipsService
    let userID: UUID
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
                    .symbolEffect(.pulse, isActive: viewModel.isBrowsing)

                Text("Bring your phone close to the host")
                    .font(.bodyFont)
                    .foregroundColor(.tertiaryColor.opacity(0.7))

                if let distance = viewModel.nearbyHostDistance {
                    Text(String(format: "%.0f cm away", distance * 100))
                        .font(.captionFont)
                        .foregroundColor(.tertiaryColor.opacity(0.5))
                }

                if viewModel.isJoining {
                    ProgressView()
                        .tint(.tertiaryColor)
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

                if let error = viewModel.error {
                    Text(error)
                        .font(.captionFont)
                        .foregroundColor(.destructiveColor)
                }

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
        .onAppear {
            viewModel.startBrowsing(touchTips: touchTips, userID: userID, sessions: sessions)
        }
        .onDisappear {
            viewModel.stopBrowsing(touchTips: touchTips)
        }
        .onChange(of: viewModel.joinedSession?.id) { _, id in
            if id != nil, let session = viewModel.joinedSession {
                onJoinRoom(session)
            }
        }
    }
}
