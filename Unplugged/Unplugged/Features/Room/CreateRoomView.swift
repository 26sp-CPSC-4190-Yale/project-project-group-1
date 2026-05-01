import SwiftUI
import UnpluggedShared

struct CreateRoomView: View {
    let sessions: SessionAPIService
    let location: LocationService
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
                RoomDescriptionField(viewModel: viewModel)

                DurationSection(value: $viewModel.duration)
                LockModeSection(viewModel: viewModel)
                LocationMetadataRow(viewModel: viewModel)

                Spacer(minLength: .spacingXl)

                CreateRoomActionButton(
                    viewModel: viewModel,
                    sessions: sessions,
                    location: location,
                    onCreateRoom: onCreateRoom
                )
            }
            .padding(.horizontal, .spacingLg)
            .padding(.top, .spacingMd)
        }
    }
}

private struct RoomDescriptionField: View {
    @Bindable var viewModel: CreateRoomViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description")
                .font(.subheadline)
                .foregroundStyle(Color.tertiaryColor.opacity(0.6))

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.description)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 88, maxHeight: 120)
                    .foregroundStyle(Color.tertiaryColor)
                    .tint(Color.tertiaryColor)
                    .padding(10)

                if viewModel.description.isEmpty {
                    Text("Optional")
                        .foregroundStyle(Color.tertiaryColor.opacity(0.3))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .background(Color.surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct LockModeSection: View {
    @Bindable var viewModel: CreateRoomViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lock Mode")
                .font(.subheadline)
                .foregroundStyle(Color.tertiaryColor.opacity(0.6))

            Picker("Lock Mode", selection: $viewModel.lockMode) {
                Text("Standard").tag(SessionLockMode.standard)
                Text("Co-Lock").tag(SessionLockMode.coLock)
            }
            .pickerStyle(.segmented)
            .tint(Color.secondaryColor)
        }
    }
}

private struct LocationMetadataRow: View {
    @Bindable var viewModel: CreateRoomViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill")
                .foregroundStyle(Color.tertiaryColor.opacity(viewModel.includeLocation ? 1 : 0.5))
                .frame(width: 24)

            Text("Location & Weather")
                .font(.body)
                .foregroundStyle(Color.tertiaryColor)

            Spacer(minLength: 0)

            Toggle("", isOn: $viewModel.includeLocation)
                .labelsHidden()
                .tint(Color.secondaryColor)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, .spacingMd)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
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
    let location: LocationService
    let onCreateRoom: (SessionResponse) -> Void

    @State private var createTask: Task<Void, Never>?

    var body: some View {
        Button {
            let title = viewModel.trimmedRoomName
            createTask?.cancel()
            createTask = Task {
                await viewModel.createRoom(title: title, sessions: sessions, location: location)
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
