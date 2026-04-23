import SwiftUI
import UnpluggedShared

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var pendingActiveSession: SessionResponse?
    @State private var pendingActiveSessionIsHost = false
    @Environment(DependencyContainer.self) private var deps

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                VStack(spacing: .spacingLg) {
                    Spacer()

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
            .fullScreenCover(isPresented: $viewModel.showJoinRoom, onDismiss: activatePendingSessionIfNeeded) {
                JoinRoomView(
                    sessions: deps.sessions,
                    touchTips: deps.touchTips
                ) { session in
                    pendingActiveSession = session
                    pendingActiveSessionIsHost = false
                    viewModel.showJoinRoom = false
                }
            }
            .fullScreenCover(isPresented: $viewModel.showCreateRoom, onDismiss: activatePendingSessionIfNeeded) {
                CreateRoomView(
                    sessions: deps.sessions,
                    touchTips: deps.touchTips
                ) { session in
                    pendingActiveSession = session
                    pendingActiveSessionIsHost = true
                    viewModel.showCreateRoom = false
                }
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

    private func activatePendingSessionIfNeeded() {
        guard let session = pendingActiveSession else { return }
        pendingActiveSession = nil
        viewModel.isHost = pendingActiveSessionIsHost
        viewModel.activeSession = session
    }
}

#Preview {
    HomeView()
        .environment(DependencyContainer())
}
