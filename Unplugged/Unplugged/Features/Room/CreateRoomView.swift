//
//  CreateRoomView.swift
//  Unplugged.Features.Room
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct CreateRoomView: View {
    @State private var viewModel = CreateRoomViewModel()
    @Environment(\.dismiss) private var dismiss
    var onCreateRoom: (MockRoom) -> Void

    var body: some View {
        VStack(spacing: .spacingMd) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.tertiaryColor.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, .spacingSm)

            Text("Create Room")
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor)
                .padding(.top, .spacingSm)

            VStack(spacing: .spacingLg) {
                // Room Name
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

                // Duration
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

                Spacer()

                // Create Button
                Button("Create") {
                    let room = viewModel.createRoom()
                    onCreateRoom(room)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canCreate)
                .opacity(viewModel.canCreate ? 1 : 0.5)
            }
            .padding(.horizontal, .spacingLg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primaryColor.opacity(0.85))
    }
}

#Preview {
    CreateRoomView { _ in }
}
