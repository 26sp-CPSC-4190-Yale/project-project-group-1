//
//  ContentView.swift
//  Unplugged
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var authViewModel = AuthViewModel()

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                MainTabView(authViewModel: authViewModel)
            } else {
                AuthView(viewModel: authViewModel)
            }
        }
        .task {
            authViewModel.configure(authService: container.auth, cache: container.cache)
            authViewModel.restoreSession()
        }
    }
}

struct MainTabView: View {
    var authViewModel: AuthViewModel

    var body: some View {
        if #available(iOS 18.0, *) {
            TabView {
                Tab("Home", systemImage: "house.fill") {
                    HomeView()
                }
                Tab("Friends", systemImage: "person.2.fill") {
                    FriendsListView()
                }
                Tab("Profile", systemImage: "person.fill") {
                    ProfileView(authViewModel: authViewModel)
                }
            }
            .tint(Color.tertiaryColor)
        } else {
            TabView {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house.fill") }
                FriendsListView()
                    .tabItem { Label("Friends", systemImage: "person.2.fill") }
                ProfileView(authViewModel: authViewModel)
                    .tabItem { Label("Profile", systemImage: "person.fill") }
            }
            .tint(Color.tertiaryColor)
        }
    }
}

#Preview {
    ContentView()
        .environment(DependencyContainer())
}
