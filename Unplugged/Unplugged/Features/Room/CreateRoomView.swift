import SwiftUI
import UnpluggedShared

struct CreateRoomView: View {
    let sessions: SessionAPIService
    let touchTips: TouchTipsService
    var onCreateRoom: (SessionResponse) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CreateRoomViewModel()

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                createFormView
            }
        }
        .errorAlert($viewModel.error)
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Color.tertiaryColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer(minLength: 0)

            Text("Create Room")
                .font(.headline)
                .foregroundStyle(Color.tertiaryColor)

            Spacer(minLength: 0)

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, .spacingMd)
        .frame(height: 52)
    }

    private var createFormView: some View {
        ScrollView {
            VStack(spacing: .spacingLg) {
                RoomNameField(viewModel: viewModel)

                DurationSection(value: $viewModel.duration)

                Spacer(minLength: .spacingXl)

                // Hands off to the unified lobby (ActiveRoomView) which owns
                // the room code display, member list, proximity advertising,
                // and the lock action.
                CreateRoomActionButton(
                    viewModel: viewModel,
                    sessions: sessions,
                    onCreateRoom: onCreateRoom
                )
            }
            .padding(.horizontal, .spacingLg)
            .padding(.top, .spacingMd)
        }
    }
}

private struct RoomNameField: View {
    @Bindable var viewModel: CreateRoomViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Room Name")
                .font(.subheadline)
                .foregroundStyle(Color.tertiaryColor.opacity(0.6))

            TextField("", text: $viewModel.roomName, prompt: placeholder)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.tertiaryColor)
                .tint(Color.tertiaryColor)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .padding(14)
                .background(Color.surfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var placeholder: Text {
        Text("Enter room name")
            .foregroundStyle(Color.tertiaryColor.opacity(0.3))
    }
}

private struct CreateRoomActionButton: View {
    let viewModel: CreateRoomViewModel
    let sessions: SessionAPIService
    let onCreateRoom: (SessionResponse) -> Void

    @State private var createTask: Task<Void, Never>?

    var body: some View {
        Button {
            let title = viewModel.trimmedRoomName
            createTask?.cancel()
            createTask = Task {
                await viewModel.createRoom(title: title, sessions: sessions)
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
            .background(viewModel.canCreate ? Color.tertiaryColor : Color.tertiaryColor.opacity(0.3))
            .foregroundStyle(Color.primaryColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canCreate)
        .onDisappear {
            createTask?.cancel()
            createTask = nil
        }
    }
}
