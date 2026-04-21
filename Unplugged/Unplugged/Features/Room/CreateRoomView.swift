import SwiftUI
import UnpluggedShared

struct CreateRoomView: View {
    let sessions: SessionAPIService
    let touchTips: TouchTipsService
    let userID: UUID
    var onCreateRoom: (SessionResponse) -> Void

    @State private var viewModel = CreateRoomViewModel()
    @State private var showDiscardConfirmation = false
    @Environment(\.dismiss) private var dismiss

    private var hasUnsavedInput: Bool {
        viewModel.createdSession == nil && !viewModel.roomName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor.opacity(0.85)
                    .ignoresSafeArea()

                if let session = viewModel.createdSession {
                    awaitingJoinView(session: session)
                } else {
                    createFormView
                }
            }
            .navigationTitle(viewModel.createdSession == nil ? "Create Room" : "Waiting for Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedInput {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(Color.tertiaryColor)
                }
            }
            .confirmationDialog(
                "Discard this room?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your room name and settings will be lost.")
            }
        }
        .errorAlert($viewModel.error)
        .onDisappear {
            viewModel.stopAdvertising(touchTips: touchTips)
        }
    }

    private var createFormView: some View {
        ScrollView {
            VStack(spacing: .spacingLg) {
                // Room Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Room Name")
                        .font(.subheadline)
                        .foregroundStyle(Color.tertiaryColor.opacity(0.6))

                    TextField("", text: $viewModel.roomName, prompt: Text("Enter room name").foregroundStyle(Color.tertiaryColor.opacity(0.3)))
                        .font(.body)
                        .foregroundStyle(Color.tertiaryColor)
                        .padding(14)
                        .background(Color.surfaceColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Duration
                VStack(alignment: .leading, spacing: .spacingSm) {
                    Text("Duration")
                        .font(.subheadline)
                        .foregroundStyle(Color.tertiaryColor.opacity(0.6))

                    HStack(spacing: .spacingSm) {
                        ForEach(viewModel.durationOptions, id: \.self) { duration in
                            Button {
                                viewModel.selectedDuration = duration
                            } label: {
                                Text(Self.formatDuration(duration))
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(viewModel.selectedDuration == duration ? Color.tertiaryColor : Color.surfaceColor)
                                    .foregroundStyle(viewModel.selectedDuration == duration ? Color.primaryColor : .tertiaryColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }

                Spacer(minLength: .spacingXl)

                // Create button
                Button {
                    Task {
                        await viewModel.createRoom(sessions: sessions)
                        if let session = viewModel.createdSession {
                            await viewModel.startAdvertising(
                                touchTips: touchTips,
                                roomID: session.session.id
                            )
                        }
                    }
                } label: {
                    Text("Create")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(viewModel.canCreate ? Color.tertiaryColor : Color.tertiaryColor.opacity(0.3))
                        .foregroundStyle(Color.primaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!viewModel.canCreate)
            }
            .padding(.horizontal, .spacingLg)
            .padding(.top, .spacingMd)
        }
    }

    private func awaitingJoinView(session: SessionResponse) -> some View {
        VStack(spacing: .spacingLg) {
            Spacer()

            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(Color.tertiaryColor)
                .symbolEffect(.pulse, isActive: viewModel.isAdvertising)

            Text("Bring phones together to invite")
                .font(.body)
                .foregroundStyle(Color.tertiaryColor.opacity(0.7))

            Spacer()

            // Room Code card
            VStack(spacing: 6) {
                Text("Room Code")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))

                Text(session.session.id.uuidString.prefix(8).uppercased())
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.tertiaryColor)
                    .kerning(4)
            }
            .padding(.spacingLg)
            .frame(maxWidth: .infinity)
            .background(Color.surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, .spacingLg)

            Spacer()

            Button {
                onCreateRoom(session)
            } label: {
                Text("Start Room")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.tertiaryColor)
                    .foregroundStyle(Color.primaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, .spacingLg)
            .padding(.bottom, .spacingMd)
        }
    }

    private static func formatDuration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}
