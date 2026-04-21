//
//  ProfileView.swift
//  Unplugged.Features.Profile
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct ProfileView: View {
    var authViewModel: AuthViewModel
    @Environment(DependencyContainer.self) private var deps
    @State private var viewModel = ProfileViewModel()
    @State private var selectedTab: ProfileViewModel.ProfileTab = .history

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .spacingMd) {
                        // Profile header
                        VStack(spacing: .spacingSm) {
                            ParticipantAvatar(name: viewModel.userName, size: 64)
                            Text(viewModel.userName)
                                .font(.title3.bold())
                                .foregroundStyle(Color.tertiaryColor)
                        }
                        .padding(.top, .spacingMd)

                        // Tab picker
                        Picker("", selection: $selectedTab) {
                            Text("Dashboard").tag(ProfileViewModel.ProfileTab.history)
                            Text("Settings").tag(ProfileViewModel.ProfileTab.settings)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, .spacingLg)

                        // Content
                        switch selectedTab {
                        case .history:
                            dashboardContent
                        case .settings:
                            settingsContent
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            await viewModel.load(stats: deps.stats, cache: deps.cache)
        }
    }

    // MARK: - Dashboard

    private var dashboardContent: some View {
        VStack(spacing: .spacingMd) {
            // Stats grid
            VStack(spacing: .spacingMd) {
                HStack(spacing: .spacingMd) {
                    StatBadge(value: "\(viewModel.hoursUnplugged)", label: "Hours Focused")
                    StatBadge(value: viewModel.rank, label: "Among Friends")
                }

                HStack(spacing: .spacingMd) {
                    StatBadge(value: "\(viewModel.totalSessions)", label: "Sessions", valueSize: 32)
                    StatBadge(value: "\(viewModel.longestStreak)", label: "Best Streak", valueSize: 32)
                    StatBadge(value: "\(viewModel.friendsCount)", label: "Friends", valueSize: 32)
                }

                HStack(spacing: .spacingMd) {
                    StatBadge(value: "\(viewModel.currentStreak)", label: "Current Streak", valueSize: 28)
                    StatBadge(value: "\(viewModel.avgSessionLength)h", label: "Avg Session", valueSize: 28)
                }
            }
            .padding(.horizontal, .spacingLg)

            // Recent Sessions
            VStack(spacing: .spacingSm) {
                HStack {
                    Text("Recent Sessions")
                        .font(.headline)
                        .foregroundStyle(Color.tertiaryColor)
                    Spacer()
                    Text("\(viewModel.totalSessions) total")
                        .font(.caption)
                        .foregroundStyle(Color.tertiaryColor.opacity(0.4))
                }
                .padding(.horizontal, .spacingLg)

                ScrollView {
                    SessionHistoryView()
                }
                .frame(maxHeight: 220)
            }
        }
    }

    // MARK: - Settings

    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    private var settingsContent: some View {
        VStack(spacing: .spacingSm) {
            settingsRow(icon: "bell.fill", title: "Notifications") {
                Toggle("", isOn: $notificationsEnabled)
                    .tint(.secondaryColor)
            }

            Button {
                viewModel.isShowingEmergencyAppsSheet = true
            } label: {
                settingsLabel(icon: "checkmark.shield.fill", title: "Emergency Apps", trailing: "Edit")
            }
            .buttonStyle(.plain)

            Link(destination: LegalFooter.termsURL) {
                settingsLabel(icon: "doc.text.fill", title: "Terms of Service", trailing: "↗")
            }

            Link(destination: LegalFooter.privacyURL) {
                settingsLabel(icon: "shield.fill", title: "Privacy Policy", trailing: "↗")
            }

            settingsRow(icon: "questionmark.circle.fill", title: "Help & Support") {
                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.3))
            }

            settingsRow(icon: "info.circle.fill", title: "About") {
                Text("v1.0")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.4))
            }

            Button(role: .destructive) {
                authViewModel.signOut()
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign Out")
                }
                .font(.body)
                .foregroundStyle(Color.destructiveColor)
                .frame(maxWidth: .infinity)
                .padding(.spacingMd)
                .background(Color.surfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, .spacingMd)

            Button(role: .destructive) {
                viewModel.isShowingDeleteAccountSheet = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Delete Account")
                }
                .font(.body)
                .foregroundStyle(Color.destructiveColor)
                .frame(maxWidth: .infinity)
                .padding(.spacingMd)
                .background(Color.surfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, .spacingLg)
        .sheet(isPresented: $viewModel.isShowingDeleteAccountSheet) {
            DeleteAccountSheet(
                onConfirm: { password in
                    await viewModel.deleteAccount(password: password, user: deps.user, auth: authViewModel)
                }
            )
        }
        .sheet(isPresented: $viewModel.isShowingEmergencyAppsSheet) {
            EmergencyAppsSettingsSheet(screenTime: deps.screenTime)
        }
    }

    private func settingsLabel(icon: String, title: String, trailing: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.tertiaryColor)
                .frame(width: 24)
            Text(title)
                .font(.body)
                .foregroundStyle(Color.tertiaryColor)
            Spacer()
            Text(trailing)
                .font(.caption)
                .foregroundStyle(Color.tertiaryColor.opacity(0.4))
        }
        .padding(.spacingMd)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private func settingsRow<Trailing: View>(icon: String, title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.tertiaryColor)
                .frame(width: 24)
            Text(title)
                .font(.body)
                .foregroundStyle(Color.tertiaryColor)
            Spacer()
            trailing()
        }
        .padding(.spacingMd)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct EmergencyAppsSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let screenTime: ScreenTimeService

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                ScrollView {
                    ScreenTimePermissionView(
                        screenTime: screenTime,
                        onDone: {}
                    )
                    .padding(.horizontal, .spacingXl)
                    .padding(.vertical, .spacingLg)
                }
            }
            .navigationTitle("Emergency Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

#Preview {
    ProfileView(authViewModel: AuthViewModel())
        .environment(DependencyContainer())
}
