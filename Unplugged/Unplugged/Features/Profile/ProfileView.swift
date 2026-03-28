//
//  ProfileView.swift
//  Unplugged.Features.Profile
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct ProfileView: View {
    var authViewModel: AuthViewModel
    @State private var viewModel = ProfileViewModel()

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: .spacingMd) {
                    // Top bar: pills + avatar
                    HStack {
                        Button(action: { viewModel.selectedTab = .history }) {
                            HStack(spacing: 6) {
                                Text("History")
                                    .font(.system(size: 15, weight: viewModel.selectedTab == .history ? .semibold : .regular))
                                Image(systemName: "book")
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(viewModel.selectedTab == .history ? .primaryColor : .tertiaryColor)
                            .padding(.horizontal, .spacingMd)
                            .padding(.vertical, .spacingSm)
                            .background(viewModel.selectedTab == .history ? Color.tertiaryColor : Color.clear)
                            .cornerRadius(20)
                        }

                        Button(action: { viewModel.selectedTab = .settings }) {
                            HStack(spacing: 6) {
                                Text("Settings")
                                    .font(.system(size: 15, weight: viewModel.selectedTab == .settings ? .semibold : .regular))
                                Image(systemName: "gearshape")
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(viewModel.selectedTab == .settings ? .primaryColor : .tertiaryColor)
                            .padding(.horizontal, .spacingMd)
                            .padding(.vertical, .spacingSm)
                            .background(viewModel.selectedTab == .settings ? Color.tertiaryColor : Color.clear)
                            .cornerRadius(20)
                        }

                        Spacer()

                        ParticipantAvatar(name: viewModel.userName, size: 48)
                    }
                    .padding(.spacingMd)
                    .liquidGlass()
                    .padding(.horizontal, .spacingLg)
                    .padding(.top, .spacingMd)

                    // Main content container — single liquid glass card
                    VStack(spacing: 0) {
                        switch viewModel.selectedTab {
                        case .history:
                            // Dashboard sub-container
                            VStack(spacing: .spacingMd) {
                                Text("Dashboard")
                                    .font(.headlineFont)
                                    .foregroundColor(.tertiaryColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                // Row 1: big stats
                                HStack(spacing: .spacingMd) {
                                    StatBadge(value: "\(viewModel.hoursUnplugged)", label: "Hours Focused")
                                    StatBadge(value: viewModel.rank, label: "Among Friends")
                                }

                                // Row 2: more stats
                                HStack(spacing: .spacingMd) {
                                    StatBadge(value: "\(viewModel.totalSessions)", label: "Sessions", valueSize: 32)
                                    StatBadge(value: "\(viewModel.longestStreak)", label: "Best Streak", valueSize: 32)
                                    StatBadge(value: "\(viewModel.friendsCount)", label: "Friends", valueSize: 32)
                                }

                                // Row 3: smaller stats
                                HStack(spacing: .spacingMd) {
                                    StatBadge(value: "\(viewModel.currentStreak)", label: "Current Streak", valueSize: 28)
                                    StatBadge(value: "\(viewModel.avgSessionLength)h", label: "Avg Session", valueSize: 28)
                                }
                            }
                            .padding(.spacingMd)

                            // Thin divider between sub-containers
                            Rectangle()
                                .fill(Color.tertiaryColor.opacity(0.08))
                                .frame(height: 1)
                                .padding(.horizontal, .spacingMd)

                            // Recent Sessions sub-container
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Recent Sessions")
                                        .font(.headlineFont)
                                        .foregroundColor(.tertiaryColor)
                                    Spacer()
                                    Text("\(viewModel.totalSessions) total")
                                        .font(.captionFont)
                                        .foregroundColor(.tertiaryColor.opacity(0.5))
                                }
                                .padding(.horizontal, .spacingMd)
                                .padding(.top, .spacingMd)
                                .padding(.bottom, .spacingSm)

                                ScrollView {
                                    SessionHistoryView()
                                }
                                .frame(maxHeight: 220)

                                Spacer().frame(height: .spacingSm)
                            }

                        case .settings:
                            SettingsSection(authViewModel: authViewModel)
                                .padding(.spacingMd)
                        }
                    }
                    .liquidGlass()
                    .padding(.horizontal, .spacingLg)

                    // Log Out
                    Button(action: { authViewModel.signOut() }) {
                        Text("Log Out")
                            .font(.headlineFont)
                            .foregroundColor(.tertiaryColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, .spacingMd)
                    }
                    .liquidGlass()
                    .padding(.horizontal, .spacingLg)
                    .padding(.bottom, .spacingXl)
                }
            }
        }
    }
}

// MARK: - Liquid Glass Modifier

private struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = .cornerRadius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.surfaceColor.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.1), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            )
    }
}

private extension View {
    func liquidGlass(cornerRadius: CGFloat = .cornerRadius) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Settings

private struct SettingsSection: View {
    var authViewModel: AuthViewModel
    @State private var notificationsEnabled = true

    var body: some View {
        VStack(spacing: .spacingSm) {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundColor(.tertiaryColor)
                Text("Notifications")
                    .font(.bodyFont)
                    .foregroundColor(.tertiaryColor)
                Spacer()
                Toggle("", isOn: $notificationsEnabled)
                    .tint(.tertiaryColor)
            }
            .padding(.spacingMd)
            .background(Color.surfaceColor.opacity(0.5))
            .cornerRadius(.cornerRadiusSm)

            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.tertiaryColor)
                Text("About")
                    .font(.bodyFont)
                    .foregroundColor(.tertiaryColor)
                Spacer()
                Text("v1.0")
                    .font(.captionFont)
                    .foregroundColor(.tertiaryColor.opacity(0.6))
            }
            .padding(.spacingMd)
            .background(Color.surfaceColor.opacity(0.5))
            .cornerRadius(.cornerRadiusSm)

            HStack {
                Image(systemName: "shield.fill")
                    .foregroundColor(.tertiaryColor)
                Text("Privacy")
                    .font(.bodyFont)
                    .foregroundColor(.tertiaryColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.captionFont)
                    .foregroundColor(.tertiaryColor.opacity(0.4))
            }
            .padding(.spacingMd)
            .background(Color.surfaceColor.opacity(0.5))
            .cornerRadius(.cornerRadiusSm)

            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.tertiaryColor)
                Text("Help & Support")
                    .font(.bodyFont)
                    .foregroundColor(.tertiaryColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.captionFont)
                    .foregroundColor(.tertiaryColor.opacity(0.4))
            }
            .padding(.spacingMd)
            .background(Color.surfaceColor.opacity(0.5))
            .cornerRadius(.cornerRadiusSm)
        }
    }
}

#Preview {
    ProfileView(authViewModel: AuthViewModel())
}
