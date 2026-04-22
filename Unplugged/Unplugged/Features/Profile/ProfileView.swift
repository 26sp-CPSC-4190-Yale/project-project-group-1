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
                        HStack {
                            Text("Profile")
                                .font(.largeTitle.bold())
                                .foregroundStyle(Color.tertiaryColor)
                            Spacer()
                        }
                        .padding(.horizontal, .spacingLg)
                        .padding(.top, .spacingSm)

                        // Profile header
                        VStack(spacing: .spacingSm) {
                            ParticipantAvatar(name: viewModel.userName, size: 64)
                            Text(viewModel.userName)
                                .font(.title3.bold())
                                .foregroundStyle(Color.tertiaryColor)
                        }
                        .padding(.top, .spacingMd)

                        // Tab picker
                        ProfileTabPicker(selection: $selectedTab)
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
            .toolbar(.hidden, for: .navigationBar)
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
            .buttonStyle(.plain)
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
            .buttonStyle(.plain)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct ProfileTabPicker: View {
    @Binding var selection: ProfileViewModel.ProfileTab
    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: .spacingSm) {
            tab(.history, label: "Dashboard")
            tab(.settings, label: "Settings")
        }
        .padding(4)
        .background(Color.surfaceColor.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func tab(_ value: ProfileViewModel.ProfileTab, label: String) -> some View {
        let isSelected = selection == value
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selection = value
            }
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.tertiaryColor.opacity(isSelected ? 1.0 : 0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.tertiaryColor, lineWidth: 1.5)
                            .matchedGeometryEffect(id: "selectionPill", in: pillNamespace)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileView(authViewModel: AuthViewModel())
        .environment(DependencyContainer())
}
