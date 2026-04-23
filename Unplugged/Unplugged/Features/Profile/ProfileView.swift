import SwiftUI
import UnpluggedShared

private struct MedalBadge: View {
    let userMedal: UserMedalResponse

    var body: some View {
        VStack(spacing: .spacingSm) {
            Text(userMedal.medal.icon)
                .font(.system(size: 36))
                .frame(width: 64, height: 64)
                .background(Color.surfaceColor)
                .clipShape(Circle())
            Text(userMedal.medal.name)
                .font(.caption)
                .foregroundStyle(Color.tertiaryColor)
                .lineLimit(1)
                .frame(maxWidth: 80)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(userMedal.medal.name). \(userMedal.medal.description)")
    }
}

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

                        VStack(spacing: .spacingSm) {
                            ParticipantAvatar(name: viewModel.userName, size: 64)
                            Text(viewModel.userName)
                                .font(.title3.bold())
                                .foregroundStyle(Color.tertiaryColor)
                        }
                        .padding(.top, .spacingMd)

                        ProfileTabPicker(selection: $selectedTab)
                            .padding(.horizontal, .spacingLg)

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
            await viewModel.load(stats: deps.stats, medals: deps.medals, cache: deps.cache)
        }
    }

    // MARK: - Dashboard

    @ViewBuilder
    private var dashboardContent: some View {
        VStack(spacing: .spacingMd) {
            statsGrid
                .padding(.horizontal, .spacingLg)

            medalsSection

            recentSessionsSection
        }
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: .spacingMd), count: 3),
            spacing: .spacingMd
        ) {
            StatBadge(value: "\(viewModel.hoursUnplugged)", label: "Hours Focused", valueSize: 28)

            NavigationLink {
                LeaderboardView()
            } label: {
                StatBadge(value: viewModel.rank, label: "Among Friends", valueSize: 28)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.tertiaryColor.opacity(0.4))
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)

            StatBadge(value: "\(viewModel.points)", label: "Points", valueSize: 28)

            StatBadge(value: "\(viewModel.totalSessions)", label: "Sessions", valueSize: 28)
            StatBadge(value: "\(viewModel.longestStreak)", label: "Best Streak", valueSize: 28)
            StatBadge(value: "\(viewModel.friendsCount)", label: "Friends", valueSize: 28)

            StatBadge(value: "\(viewModel.currentStreak)", label: "Current Streak", valueSize: 28)
            StatBadge(value: viewModel.avgFocusedSessionLabel, label: "Avg Session", valueSize: 28)
            StatBadge(value: "\(viewModel.earlyLeaveCount)", label: "Left Early", valueSize: 28)
        }
    }

    @ViewBuilder
    private var medalsSection: some View {
        NavigationLink {
            MedalsGalleryView()
        } label: {
            VStack(spacing: .spacingSm) {
                HStack {
                    Text("Medals")
                        .font(.headline)
                        .foregroundStyle(Color.tertiaryColor)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(viewModel.medals.count)")
                            .font(.caption)
                            .foregroundStyle(Color.tertiaryColor.opacity(0.4))
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Color.tertiaryColor.opacity(0.3))
                    }
                }
                .padding(.horizontal, .spacingLg)

                if viewModel.medals.isEmpty {
                    HStack {
                        Text("Tap to view all medals")
                            .font(.caption)
                            .foregroundStyle(Color.tertiaryColor.opacity(0.5))
                        Spacer()
                    }
                    .padding(.horizontal, .spacingLg)
                    .padding(.vertical, .spacingSm)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: .spacingMd) {
                            ForEach(viewModel.medals, id: \.medal.id) { userMedal in
                                MedalBadge(userMedal: userMedal)
                            }
                        }
                        .padding(.horizontal, .spacingLg)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var recentSessionsSection: some View {
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

    // MARK: - Settings

    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @State private var isShowingAboutSheet = false

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

            Button {
                isShowingAboutSheet = true
            } label: {
                settingsLabel(icon: "info.circle.fill", title: "About", trailing: "v1.0")
            }
            .buttonStyle(.plain)

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
        .sheet(isPresented: $isShowingAboutSheet) {
            AboutSheet()
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

private struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: .spacingMd) {
                        Text("About Unplugged")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.tertiaryColor)

                        Text("Version 1.0")
                            .font(.subheadline)
                            .foregroundStyle(Color.tertiaryColor.opacity(0.6))

                        Text("Unplugged helps you reclaim your focus with friends. Start a session, put your phone down together, and build the muscle of being present. Real connection, one unplugged hour at a time.")
                            .font(.body)
                            .foregroundStyle(Color.tertiaryColor)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Every session you complete counts — toward your streak, your medals, and the people on the other side of the table. We built Unplugged because the best moments in our lives never happened through a screen.")
                            .font(.body)
                            .foregroundStyle(Color.tertiaryColor.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: .spacingSm) {
                            Link("Terms of Service", destination: LegalFooter.termsURL)
                            Text("·")
                                .foregroundStyle(Color.tertiaryColor.opacity(0.4))
                            Link("Privacy Policy", destination: LegalFooter.privacyURL)
                        }
                        .font(.footnote)
                        .tint(Color.tertiaryColor.opacity(0.9))
                        .padding(.top, .spacingSm)
                    }
                    .padding(.horizontal, .spacingLg)
                    .padding(.vertical, .spacingLg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
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
