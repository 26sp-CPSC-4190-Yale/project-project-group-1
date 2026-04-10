import SwiftUI
import UnpluggedShared

struct CreateRoomView: View {
    let sessions: SessionAPIService
    let touchTips: TouchTipsService
    let userID: UUID
    var onCreateRoom: (SessionResponse) -> Void

    @State private var viewModel = CreateRoomViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: .spacingMd) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.tertiaryColor.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, .spacingSm)

            if let session = viewModel.createdSession {
                awaitingJoinView(session: session)
            } else {
                createFormView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primaryColor.opacity(0.85))
        .onDisappear {
            viewModel.stopAdvertising(touchTips: touchTips)
        }
    }

    private var createFormView: some View {
        VStack(spacing: .spacingMd) {
            Text("Create Room")
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor)
                .padding(.top, .spacingSm)

            VStack(spacing: .spacingLg) {
                VStack(alignment: .leading, spacing: .spacingSm) {
                    Text("Room Name")
                        .font(.captionFont)
                        .foregroundColor(.tertiaryColor.opacity(0.6))

                    TextField("", text: $viewModel.roomName, prompt: Text("Enter room name").foregroundColor(.tertiaryColor.opacity(0.4)))
                        .font(.bodyFont)
                        .foregroundColor(.tertiaryColor)
                        .padding(.spacingMd)
                        .background(Color.surfaceColor)
                        .cornerRadius(.cornerRadiusSm)
                }

                VStack(alignment: .leading, spacing: .spacingSm) {
                    Text("Duration")
                        .font(.captionFont)
                        .foregroundColor(.tertiaryColor.opacity(0.6))

                    HStack(spacing: .spacingSm) {
                        ForEach(viewModel.durationOptions, id: \.self) { duration in
                            Button(action: { viewModel.selectedDuration = duration }) {
                                Text(duration >= 60 ? "\(duration / 60)h" : "\(duration)m")
                                    .font(.bodyFont)
                                    .foregroundColor(viewModel.selectedDuration == duration ? .primaryColor : .tertiaryColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, .spacingSm)
                                    .background(viewModel.selectedDuration == duration ? Color.tertiaryColor : Color.surfaceColor)
                                    .cornerRadius(.cornerRadiusSm)
                            }
                        }
                    }
                }

                if let error = viewModel.error {
                    Text(error)
                        .font(.captionFont)
                        .foregroundColor(.destructiveColor)
                }

                Spacer()

                Button("Create") {
                    Task {
                        await viewModel.createRoom(sessions: sessions)
                        if let session = viewModel.createdSession {
                            await viewModel.startAdvertising(
                                touchTips: touchTips,
                                roomID: session.session.id
                            )
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canCreate)
                .opacity(viewModel.canCreate ? 1 : 0.5)
            }
            .padding(.horizontal, .spacingLg)
        }
    }

    private func awaitingJoinView(session: SessionResponse) -> some View {
        VStack(spacing: .spacingLg) {
            Text("Waiting for Players")
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor)
                .padding(.top, .spacingSm)

            Spacer()

            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundColor(.tertiaryColor)
                .symbolEffect(.pulse, isActive: viewModel.isAdvertising)

            Text("Bring phones together to invite")
                .font(.bodyFont)
                .foregroundColor(.tertiaryColor.opacity(0.7))

            Spacer()

            VStack(spacing: .spacingSm) {
                Text("Room Code")
                    .font(.captionFont)
                    .foregroundColor(.tertiaryColor.opacity(0.6))

                Text(session.session.id.uuidString.prefix(8).uppercased())
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.tertiaryColor)
                    .kerning(4)
            }

            Spacer()

            Button("Start Room") {
                onCreateRoom(session)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, .spacingLg)
            .padding(.bottom, .spacingMd)
        }
        .padding(.horizontal, .spacingLg)
    }
}
