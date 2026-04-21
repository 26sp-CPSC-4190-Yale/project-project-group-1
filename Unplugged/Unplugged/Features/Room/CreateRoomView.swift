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
        !viewModel.roomName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor.opacity(0.85)
                    .ignoresSafeArea()

                createFormView
            }
            .navigationTitle("Create Room")
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

                // Create button hands straight off to the unified lobby
                // (ActiveRoomView) — that view owns the room code display,
                // member list, proximity advertising, and the lock action.
                Button {
                    Task {
                        await viewModel.createRoom(sessions: sessions)
                        if let session = viewModel.createdSession {
                            onCreateRoom(session)
                        }
                    }
                } label: {
                    Group {
                        if viewModel.isCreating {
                            ProgressView().tint(.primaryColor)
                        } else {
                            Text("Create")
                        }
                    }
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

    private static func formatDuration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}
