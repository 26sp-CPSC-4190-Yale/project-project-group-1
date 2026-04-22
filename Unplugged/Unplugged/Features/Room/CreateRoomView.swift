import SwiftUI
import UnpluggedShared

struct CreateRoomView: View {
    let sessions: SessionAPIService
    let touchTips: TouchTipsService
    let userID: UUID
    var onCreateRoom: (SessionResponse) -> Void

    @State private var viewModel = CreateRoomViewModel()
    @State private var roomName = ""
    @State private var createTask: Task<Void, Never>?

    private var trimmedRoomName: String {
        roomName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedRoomName.isEmpty && !viewModel.isCreating
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

                    TextField("", text: $roomName, prompt: Text("Enter room name").foregroundStyle(Color.tertiaryColor.opacity(0.3)))
                        .font(.body)
                        .foregroundStyle(Color.tertiaryColor)
                        .submitLabel(.done)
                        .padding(14)
                        .background(Color.surfaceColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .onChange(of: roomName) { _, _ in
                            ResponsivenessDiagnostics.event("room_name_type")
                        }
                }

                DurationSection(value: $viewModel.duration)

                Spacer(minLength: .spacingXl)

                // Create button hands straight off to the unified lobby
                // (ActiveRoomView) — that view owns the room code display,
                // member list, proximity advertising, and the lock action.
                Button {
                    createTask?.cancel()
                    createTask = Task {
                        await viewModel.createRoom(title: trimmedRoomName, sessions: sessions)
                        guard !Task.isCancelled else { return }
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
                    .background(canCreate ? Color.tertiaryColor : Color.tertiaryColor.opacity(0.3))
                    .foregroundStyle(Color.primaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canCreate)
            }
            .padding(.horizontal, .spacingLg)
            .padding(.top, .spacingMd)
        }
        .onDisappear {
            createTask?.cancel()
            createTask = nil
        }
    }

}
