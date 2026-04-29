import SwiftUI

struct ContentView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var authViewModel = AuthViewModel()
    @State private var onboardingComplete = OnboardingViewModel.hasCompleted

    var body: some View {
        Group {
            if !onboardingComplete {
                OnboardingView(onFinish: { onboardingComplete = true })
            } else if authViewModel.isAuthenticated {
                MainTabView(authViewModel: authViewModel)
            } else {
                AuthView(viewModel: authViewModel)
            }
        }
        .task {
            guard !authViewModel.isConfigured else { return }
            authViewModel.configure(
                authService: container.auth,
                userService: container.user,
                cache: container.cache,
                sessionOrchestrator: container.sessionOrchestrator
            )
            await authViewModel.restoreSession()
        }
    }
}

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    var authViewModel: AuthViewModel
    @State private var selectedTab: MainTab = .home
    @State private var friendsRefreshToken = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(MainTab.home)

            FriendsListView(refreshToken: friendsRefreshToken)
                .tabItem { Label("Friends", systemImage: "person.2.fill") }
                .tag(MainTab.friends)

            ProfileView(authViewModel: authViewModel)
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(MainTab.profile)
        }
        .tint(.tertiaryColor)
        .onChange(of: selectedTab) { _, newTab in
            guard newTab == .friends else { return }
            friendsRefreshToken += 1
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            Task { await AppDelegate.reportPresence(isActive: false) }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await AppDelegate.reportPresence(isActive: true)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private enum MainTab: Hashable {
        case home
        case friends
        case profile
    }
}

#Preview {
    ContentView()
        .environment(DependencyContainer())
}
