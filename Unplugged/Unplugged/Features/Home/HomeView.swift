import SwiftUI
import UnpluggedShared

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
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
                        Button(action: { viewModel.showCreateRoom = true }) {
                            VStack(spacing: .spacingSm) {
                                Image(systemName: "plus")
                                    .font(.system(size: 36, weight: .medium))
                                    .foregroundStyle(Color.tertiaryColor)
                            }
                        }
                        .buttonStyle(LiquidGlassButtonStyle())

                        Text("Create Room")
                            .font(.headline)
                            .foregroundStyle(Color.tertiaryColor)
                            .onTapGesture { viewModel.showCreateRoom = true }

                        Spacer()
                            .frame(height: .spacingMd)

                        Button(action: { viewModel.showJoinRoom = true }) {
                            VStack(spacing: .spacingSm) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 36, weight: .medium))
                                    .foregroundStyle(Color.tertiaryColor)
                            }
                        }
                        .buttonStyle(LiquidGlassButtonStyle())

                        Text("Join Room")
                            .font(.headline)
                            .foregroundStyle(Color.tertiaryColor)
                            .onTapGesture { viewModel.showJoinRoom = true }
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
            .sheet(isPresented: $viewModel.showCreateRoom) {
                CreateRoomView(
                    sessions: deps.sessions,
                    touchTips: deps.touchTips,
                    userID: UUID() // Pass a dummy ID or refactor CreateRoomView to not require it
                ) { session in
                    viewModel.showCreateRoom = false
                    viewModel.isHost = true
                    viewModel.activeSession = session
                }
                .presentationDetents([.medium, .large])
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
}

#Preview {
    HomeView()
        .environment(DependencyContainer())
}
