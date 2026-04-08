//
//  HomeView.swift
//  Unplugged.Features.Home
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("UNPLUGGED")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.tertiaryColor)
                            .tracking(2)

                        Spacer()
                    }
                    .padding(.horizontal, .spacingLg)
                    .padding(.top, .spacingMd)

                    Spacer()
                        .frame(height: geo.size.height * 0.28 - 80)

                    // Create Room at 1/3
                    Button(action: { viewModel.showCreateRoom = true }) {
                        VStack(spacing: .spacingSm) {
                            Image(systemName: "plus")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundColor(.tertiaryColor)
                        }
                    }
                    .buttonStyle(LiquidGlassButtonStyle())

                    Text("Create room")
                        .font(.headlineFont)
                        .foregroundColor(.tertiaryColor)
                        .padding(.top, .spacingSm)

                    Spacer()
                        .frame(height: geo.size.height * 0.15)

                    // Join Room at 2/3
                    Button(action: { viewModel.showJoinRoom = true }) {
                        VStack(spacing: .spacingSm) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundColor(.tertiaryColor)
                        }
                    }
                    .buttonStyle(LiquidGlassButtonStyle())

                    Text("Join room")
                        .font(.headlineFont)
                        .foregroundColor(.tertiaryColor)
                        .padding(.top, .spacingSm)

                    Spacer()
                }
            }
        }
        .sheet(isPresented: $viewModel.showJoinRoom) {
            JoinRoomView { room in
                viewModel.showJoinRoom = false
                viewModel.activeRoom = room
            }
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $viewModel.showCreateRoom) {
            CreateRoomView { room in
                viewModel.showCreateRoom = false
                viewModel.activeRoom = room
            }
            .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(item: $viewModel.activeRoom) { room in
            ActiveRoomView(room: room) {
                viewModel.activeRoom = nil
            }
        }
    }
}

#Preview {
    HomeView()
}
