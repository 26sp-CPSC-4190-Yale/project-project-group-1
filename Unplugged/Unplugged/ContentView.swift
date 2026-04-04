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
    }
}

#Preview {
    ContentView()
        .environment(DependencyContainer())
}
