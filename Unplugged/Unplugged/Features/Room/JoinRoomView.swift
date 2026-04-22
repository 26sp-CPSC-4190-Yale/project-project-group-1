import SwiftUI
import UnpluggedShared

struct JoinRoomView: View {
    let sessions: SessionAPIService
    let touchTips: TouchTipsService
    var onJoinRoom: (SessionResponse) -> Void

    @State private var viewModel = JoinRoomViewModel()
    @State private var manualJoinTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor.opacity(0.85)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .spacingLg) {
                        // Room code entry (primary action)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Room Code")
                                .font(.subheadline)
                                .foregroundStyle(Color.tertiaryColor.opacity(0.6))

                            TextField("", text: $viewModel.manualCode, prompt: Text("Enter code").foregroundStyle(Color.tertiaryColor.opacity(0.3)))
                                .font(.body)
                                .foregroundStyle(Color.tertiaryColor)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(Color.surfaceColor)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            manualJoinTask?.cancel()
                            manualJoinTask = Task {
                                await viewModel.joinWithCode(sessions: sessions, touchTips: touchTips)
                            }
                        } label: {
                            Text("Join")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(viewModel.canJoinManually ? Color.tertiaryColor : Color.tertiaryColor.opacity(0.3))
                                .foregroundStyle(Color.primaryColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(!viewModel.canJoinManually)

                        // Divider
                        HStack {
                            Rectangle()
                                .fill(Color.tertiaryColor.opacity(0.15))
                                .frame(height: 1)
                            Text("or")
                                .font(.caption)
                                .foregroundStyle(Color.tertiaryColor.opacity(0.4))
                            Rectangle()
                                .fill(Color.tertiaryColor.opacity(0.15))
                                .frame(height: 1)
                        }
                        .padding(.vertical, .spacingSm)

                        // TouchTips / proximity join
                        VStack(spacing: .spacingMd) {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.tertiaryColor)
                                .symbolEffect(.pulse, isActive: viewModel.isListening)

                            Text(viewModel.hasFoundRoom ? "Room found" : "Bring your phone close to the host")
                                .font(.subheadline)
                                .foregroundStyle(viewModel.hasFoundRoom ? .green : .tertiaryColor.opacity(0.7))

                            if viewModel.isJoining {
                                ProgressView()
                                    .tint(.tertiaryColor)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, .spacingLg)
                        .background(Color.surfaceColor.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, .spacingLg)
                    .padding(.top, .spacingMd)
                }
            }
            .navigationTitle("Join Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .errorAlert($viewModel.error)
        .onAppear {
            viewModel.startListening(touchTips: touchTips, sessions: sessions)
        }
        .onDisappear {
            manualJoinTask?.cancel()
            manualJoinTask = nil
            viewModel.stopListening(touchTips: touchTips)
        }
        .onChange(of: viewModel.joinedSession?.id) { _, id in
            if id != nil, let session = viewModel.joinedSession {
                onJoinRoom(session)
            }
        }
    }
}
