import SwiftUI
import UnpluggedShared

struct HomeView: View {
    @State private var showJoinRoom = false
    @State private var showCreateRoom = false
    @State private var activeSession: SessionResponse?
    @State private var isHost = false
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
                            showCreateRoom = true
                        }

                        Spacer()
                            .frame(height: .spacingMd)

                        homeAction(title: "Join Room", systemImage: "arrow.right") {
                            showJoinRoom = true
                        }
                    }

                    Spacer()
                }
            }
            .navigationTitle("UNPLUGGED")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("UNPLUGGED")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .fullScreenCover(isPresented: $showJoinRoom, onDismiss: activatePendingSessionIfNeeded) {
                JoinRoomView(
                    sessions: deps.sessions,
                    touchTips: deps.touchTips
                ) { session in
                    pendingActiveSession = session
                    pendingActiveSessionIsHost = false
                    showJoinRoom = false
                }
                .environment(deps)
            }
            .fullScreenCover(isPresented: $showCreateRoom, onDismiss: activatePendingSessionIfNeeded) {
                CreateRoomView(
                    sessions: deps.sessions
                ) { session in
                    pendingActiveSession = session
                    pendingActiveSessionIsHost = true
                    showCreateRoom = false
                }
                .environment(deps)
            }
            .fullScreenCover(item: $activeSession) { session in
                ActiveRoomView(session: session, isHost: isHost) {
                    activeSession = nil
                    isHost = false
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
        isHost = pendingActiveSessionIsHost
        activeSession = session
    }
}

#Preview {
    HomeView()
        .environment(DependencyContainer())
}
