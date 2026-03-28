//
//  JoinRoomView.swift
//  Unplugged.Features.Room
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct JoinRoomView: View {
    @State private var viewModel = JoinRoomViewModel()
    @Environment(\.dismiss) private var dismiss
    var onJoinRoom: (MockRoom) -> Void

    var body: some View {
        VStack(spacing: .spacingMd) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.tertiaryColor.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, .spacingSm)

            Text("Open Rooms")
                .font(.headlineFont)
                .foregroundColor(.tertiaryColor)
                .padding(.top, .spacingSm)

            ScrollView {
                VStack(spacing: .spacingSm) {
                    ForEach(viewModel.openRooms) { room in
                        Button(action: { onJoinRoom(room) }) {
                            Text(room.name)
                                .font(.bodyFont)
                                .foregroundColor(.tertiaryColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, .spacingMd)
                                .background(Color.surfaceColor)
                                .cornerRadius(.cornerRadiusSm)
                        }
                    }
                }
                .padding(.horizontal, .spacingLg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primaryColor.opacity(0.85))
    }
}

#Preview {
    JoinRoomView { _ in }
}
