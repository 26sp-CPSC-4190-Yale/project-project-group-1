import SwiftUI
import UnpluggedShared

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var createRoomDetent: PresentationDetent = .medium
    @Environment(DependencyContainer.self) private var deps

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                VStack(spacing: .spacingLg) {
                    Spacer()

                    // Central action area
                    VStack(spacing: .spacingXl) {
                        homeAction(title: "Create Room", systemImage: "plus") {
                            viewModel.showCreateRoom = true
                        }

                        Spacer()
                            .frame(height: .spacingMd)

                        homeAction(title: "Join Room", systemImage: "arrow.right") {
                            viewModel.showJoinRoom = true
                        }
                    }

                    Spacer()
                }
            }
            .navigationTitle("UNPLUGGED")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $viewModel.showJoinRoom) {
                JoinRoomView(
                    sessions: deps.sessions,
                    touchTips: deps.touchTips
                ) { session in
                    viewModel.showJoinRoom = false
                    viewModel.isHost = false
                    viewModel.activeSession = session
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $viewModel.showCreateRoom, onDismiss: {
                createRoomDetent = .medium
            }) {
                CreateRoomView(
                    sessions: deps.sessions,
                    touchTips: deps.touchTips,
                    userID: UUID(), // Pass a dummy ID or refactor CreateRoomView to not require it
                    detent: $createRoomDetent
                ) { session in
                    viewModel.showCreateRoom = false
                    viewModel.isHost = true
                    // Stagger the fullScreenCover presentation so UIKit finishes the
                    // sheet dismiss animation before it tries to push the new container.
                    // Presenting both in the same frame causes "containerToPush is nil"
                    // and compounds the main-thread stall from lobby setup.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        viewModel.activeSession = session
                    }
                }
                .presentationDetents([.medium, .large], selection: $createRoomDetent)
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
            .fullScreenCover(item: $viewModel.activeSession) { session in
                ActiveRoomView(session: session, isHost: viewModel.isHost) {
                    viewModel.activeSession = nil
                    viewModel.isHost = false
                }
                .environment(deps)
            }
        }
    }

    private func homeAction(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: .spacingSm) {
                ZStack {
                    Circle()
                        .fill(Color.surfaceColor.opacity(0.7))
                        .overlay(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.15), Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)

                    Image(systemName: systemImage)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(Color.tertiaryColor)
                }
                .frame(width: 140, height: 140)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.tertiaryColor)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView()
        .environment(DependencyContainer())
}
