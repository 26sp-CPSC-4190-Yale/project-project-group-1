import SwiftUI
import UnpluggedShared

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @Environment(DependencyContainer.self) private var deps

    private var currentUserID: UUID {
        deps.cache.readUser()?.id ?? UUID()
    }

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
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
            JoinRoomView(
                sessions: deps.sessions,
                touchTips: deps.touchTips,
                userID: currentUserID
            ) { session in
                viewModel.showJoinRoom = false
                viewModel.activeSession = session
            }
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $viewModel.showCreateRoom) {
            CreateRoomView(
                sessions: deps.sessions,
                touchTips: deps.touchTips,
                userID: currentUserID
            ) { session in
                viewModel.showCreateRoom = false
                viewModel.activeSession = session
            }
            .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(item: $viewModel.activeSession) { session in
            ActiveRoomView(session: session, currentUserID: currentUserID) {
                viewModel.activeSession = nil
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(DependencyContainer())
}
