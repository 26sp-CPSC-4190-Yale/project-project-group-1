import SwiftUI
import UnpluggedShared

struct HomeView: View {
    @State private var showJoinRoom = false
    @State private var showCreateRoom = false
    @State private var activeRoom: ActiveRoomPresentation?
    @State private var pendingActiveRoom: ActiveRoomPresentation?
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
                    pendingActiveRoom = ActiveRoomPresentation(session: session, isHost: false)
                    showJoinRoom = false
                }
                .environment(deps)
            }
            .fullScreenCover(isPresented: $showCreateRoom, onDismiss: activatePendingSessionIfNeeded) {
                CreateRoomView(
                    sessions: deps.sessions
                ) { session in
                    pendingActiveRoom = ActiveRoomPresentation(session: session, isHost: true)
                    showCreateRoom = false
                }
                .environment(deps)
            }
            .fullScreenCover(item: $activeRoom) { room in
                ActiveRoomView(session: room.session, isHost: room.isHost) {
                    activeRoom = nil
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
        guard let room = pendingActiveRoom else { return }
        pendingActiveRoom = nil
        activeRoom = room
    }
}

private struct ActiveRoomPresentation: Identifiable {
    let session: SessionResponse
    let isHost: Bool

    var id: UUID { session.id }
}

#Preview {
    HomeView()
        .environment(DependencyContainer())
}
