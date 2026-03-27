//
//  ActiveRoomView.swift
//  Unplugged.Features.Room
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

// TODO: Integrate CountdownView into center area; show remaining time instead of static icon

import SwiftUI

struct ActiveRoomView: View {
    let room: MockRoom
    var onEnd: () -> Void

    @State private var viewModel: ActiveRoomViewModel
    @Environment(\.dismiss) private var dismiss

    init(room: MockRoom, onEnd: @escaping () -> Void) {
        self.room = room
        self.onEnd = onEnd
        _viewModel = State(initialValue: ActiveRoomViewModel(room: room))
    }

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            VStack(spacing: .spacingLg) {
                // Header
                HStack {
                    Button(action: {
                        onEnd()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.tertiaryColor)
                    }
                    Spacer()
                    Text(room.name)
                        .font(.headlineFont)
                        .foregroundColor(.tertiaryColor)
                    Spacer()
                    Image(systemName: "xmark")
                        .font(.system(size: 18))
                        .opacity(0)
                }
                .padding(.horizontal, .spacingLg)

                Spacer()

                // Center — large liquid glass circle
                Button(action: {}) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.tertiaryColor)
                }
                .buttonStyle(LiquidGlassButtonStyle(diameter: 180))

                Spacer()

                // Participants
                VStack(alignment: .leading, spacing: .spacingMd) {
                    Text("Members")
                        .font(.headlineFont)
                        .foregroundColor(.tertiaryColor)
                        .padding(.horizontal, .spacingLg)

                    VStack(spacing: .spacingSm) {
                        ForEach(viewModel.participants) { participant in
                            HStack(spacing: .spacingMd) {
                                ParticipantAvatar(name: participant.name, size: 40)

                                Text(participant.name)
                                    .font(.bodyFont)
                                    .foregroundColor(.tertiaryColor)

                                if participant.isHost {
                                    Text("Host")
                                        .font(.captionFont)
                                        .foregroundColor(.tertiaryColor.opacity(0.6))
                                }

                                Spacer()

                                // Kick button (host only, not for self)
                                if viewModel.isHost && !participant.isHost {
                                    Button(action: {
                                        viewModel.kickParticipant(participant)
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(.destructiveColor)
                                    }
                                }
                            }
                            .padding(.horizontal, .spacingLg)
                            .padding(.vertical, .spacingSm)
                        }
                    }
                }

                Spacer()

                // End Room
                Button("End Room") {
                    viewModel.showEndConfirmation = true
                }
                .buttonStyle(DestructiveButtonStyle())
                .padding(.horizontal, .spacingLg)
                .padding(.bottom, .spacingMd)
            }
        }
        .alert("End Room?", isPresented: $viewModel.showEndConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("End", role: .destructive) {
                onEnd()
                dismiss()
            }
        } message: {
            Text("This will end the session for everyone.")
        }
    }
}

#Preview {
    ActiveRoomView(room: MockRoom(id: "1", name: "Study Session", host: "You", participantCount: 3, duration: 60)) {}
}
