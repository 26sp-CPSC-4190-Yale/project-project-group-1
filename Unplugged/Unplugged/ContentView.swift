//
//  ContentView.swift
//  Unplugged
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

// TODO: Add onboarding gate (check first launch); persist auth state across app restarts

import SwiftUI

struct ContentView: View {
    @State private var authViewModel = AuthViewModel()

    var body: some View {
        if authViewModel.isAuthenticated {
            MainTabView(authViewModel: authViewModel)
        } else {
            AuthView(viewModel: authViewModel)
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
}
