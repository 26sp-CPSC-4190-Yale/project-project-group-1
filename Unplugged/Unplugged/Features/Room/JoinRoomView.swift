import SwiftUI
import UnpluggedShared

struct JoinRoomView: View {
    let sessions: SessionAPIService
    let touchTips: TouchTipsService
    var onJoinRoom: (SessionResponse) -> Void

    @State private var viewModel = JoinRoomViewModel()
    @State private var manualJoinTask: Task<Void, Never>?
    @State private var proximityStartTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    private let proximityListenDelay: UInt64 = 1_500_000_000

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: .spacingLg) {
                        roomCodeField

                        joinButton

                        orDivider

                        proximitySection
                    }
                    .padding(.horizontal, .spacingLg)
                    .padding(.top, .spacingMd)
                }
            }
        }
        .errorAlert($viewModel.error)
        .onAppear { scheduleProximityListening() }
        .onDisappear {
            manualJoinTask?.cancel()
            manualJoinTask = nil
            proximityStartTask?.cancel()
            proximityStartTask = nil
            viewModel.stopListening(touchTips: touchTips)
        }
        .onChange(of: viewModel.manualCode.isEmpty) { _, isEmpty in
            // only react to empty/non-empty transitions, not every keystroke,
            // otherwise rapid type-then-backspace churns the UWB session (P3-19)
            if isEmpty {
                scheduleProximityListening()
            } else {
                proximityStartTask?.cancel()
                proximityStartTask = nil
                if viewModel.isListening {
                    viewModel.stopListening(touchTips: touchTips)
                }
            }
        }
        .onChange(of: viewModel.joinedSession?.id) { _, id in
            if id != nil, let session = viewModel.joinedSession {
                onJoinRoom(session)
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                manualJoinTask?.cancel()
                manualJoinTask = nil
                proximityStartTask?.cancel()
                proximityStartTask = nil
                viewModel.stopListening(touchTips: touchTips)
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

            Text("Join Room")
                .font(.headline)
                .foregroundStyle(Color.tertiaryColor)

            Spacer(minLength: 0)

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, .spacingMd)
        .frame(height: 52)
    }

    private var roomCodeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Room Code")
                .font(.subheadline)
                .foregroundStyle(Color.tertiaryColor.opacity(0.6))

            // Binding normalizes once per setter call; doing this in a property
            // didSet would re-publish the @Observable value and double-render the field
            TextField("", text: Binding(
                get: { viewModel.manualCode },
                set: { viewModel.manualCode = JoinRoomViewModel.normalizedRoomCode($0) }
            ), prompt: codePlaceholder)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.tertiaryColor)
                .tint(Color.tertiaryColor)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .padding(14)
                .background(Color.surfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var codePlaceholder: Text {
        Text("Enter code")
            .foregroundStyle(Color.tertiaryColor.opacity(0.3))
    }

    private var joinButton: some View {
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
    }

    private var orDivider: some View {
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
    }

    private var proximitySection: some View {
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

    private func scheduleProximityListening() {
        guard viewModel.manualCode.isEmpty, !viewModel.isListening else { return }
        proximityStartTask?.cancel()
        proximityStartTask = Task {
            try? await Task.sleep(nanoseconds: proximityListenDelay)
            guard !Task.isCancelled, viewModel.manualCode.isEmpty else { return }
            viewModel.startListening(touchTips: touchTips, sessions: sessions)
        }
    }
}
