import SwiftUI
import UnpluggedShared

@MainActor
@Observable
final class FriendProfileViewModel {
    var profile: FriendProfileResponse?
    var isLoading = false
    var isSendingNudge = false
    var isRemovingFriend = false
    var error: String?

    func load(service: FriendAPIService, friendID: UUID) async {
        isLoading = true
        error = nil
        do {
            profile = try await service.getProfile(id: friendID)
        } catch is CancellationError {
        } catch {
            self.error = "Could not load profile"
        }
        isLoading = false
    }

    func sendNudge(service: FriendAPIService, friendID: UUID) async {
        guard !isSendingNudge else { return }

        isSendingNudge = true
        defer { isSendingNudge = false }

        do {
            try await service.nudge(friendID: friendID)
        } catch {
            self.error = "Could not send nudge"
        }
    }

    func removeFriend(service: FriendAPIService, friendID: UUID) async -> Bool {
        guard !isRemovingFriend else { return false }

        isRemovingFriend = true
        defer { isRemovingFriend = false }

        do {
            try await service.removeFriend(id: friendID)
            return true
        } catch {
            self.error = "Could not remove friend"
            return false
        }
    }
}

struct FriendProfileView: View {
    let friend: FriendResponse

    @Environment(DependencyContainer.self) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = FriendProfileViewModel()
    @State private var confirmRemoveFriend = false

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: .spacingLg) {
                    header

                    if let stats = viewModel.profile?.stats {
                        statsGrid(stats: stats)
                            .padding(.horizontal, .spacingLg)
                    } else if viewModel.isLoading {
                        ProgressView()
                            .tint(.tertiaryColor)
                            .padding(.top, .spacingLg)
                    }

                    if let medals = viewModel.profile?.medals, !medals.isEmpty {
                        medalsSection(medals: medals)
                    }

                    if let error = viewModel.error, viewModel.profile == nil {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Color.destructiveColor)
                            .padding(.top, .spacingLg)
                    }
                }
                .padding(.bottom, .spacingLg)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await viewModel.load(service: deps.friends, friendID: friend.id)
        }
        .refreshable {
            await viewModel.load(service: deps.friends, friendID: friend.id)
        }
        .confirmationDialog(
            "Remove this friend?",
            isPresented: $confirmRemoveFriend,
            titleVisibility: .visible
        ) {
            Button("Remove Friend", role: .destructive) {
                Task {
                    let removed = await viewModel.removeFriend(
                        service: deps.friends,
                        friendID: friend.id
                    )
                    guard removed else { return }
                    NotificationCenter.default.post(name: .unpluggedFriendsDidChange, object: nil)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove \(friend.username) from your friends list.")
        }
        .errorAlert($viewModel.error)
    }

    private var header: some View {
        VStack(spacing: .spacingMd) {
            ParticipantAvatar(name: friend.username, size: 80)
                .padding(.top, .spacingXl)

            Text(friend.username)
                .font(.title.bold())
                .foregroundStyle(Color.tertiaryColor)

            HStack(spacing: 6) {
                Circle()
                    .fill(presenceColor)
                    .frame(width: 8, height: 8)
                Text(presenceLabel)
                    .font(.subheadline)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
            }

            if friend.status == "accepted" {
                Button {
                    Task {
                        await viewModel.sendNudge(service: deps.friends, friendID: friend.id)
                    }
                } label: {
                    Group {
                        if viewModel.isSendingNudge {
                            ProgressView()
                                .tint(.primaryColor)
                        } else {
                            Label("Nudge", systemImage: "bell.badge.fill")
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, .spacingSm)

                Button("Remove Friend", role: .destructive) {
                    confirmRemoveFriend = true
                }
                .buttonStyle(DestructiveButtonStyle())
                .disabled(viewModel.isRemovingFriend)
            }
        }
    }

    private func statsGrid(stats: UserStatsResponse) -> some View {
        VStack(spacing: .spacingMd) {
            HStack(spacing: .spacingMd) {
                StatBadge(value: "\(stats.hoursUnplugged)", label: "Hours Focused")
                StatBadge(value: "\(stats.totalSessions)", label: "Sessions")
            }
            HStack(spacing: .spacingMd) {
                StatBadge(value: "\(stats.longestStreak)", label: "Best Streak", valueSize: 32)
                StatBadge(value: "\(stats.currentStreak)", label: "Current Streak", valueSize: 32)
                StatBadge(value: avgLabel(stats: stats), label: "Avg Session", valueSize: 32)
            }
        }
    }

    private func avgLabel(stats: UserStatsResponse) -> String {
        let mins = stats.avgSessionLengthMinutes
        guard mins > 0 else { return "0m" }
        if mins >= 60 {
            return String(format: "%.1fh", mins / 60.0)
        }
        return "\(Int(mins.rounded()))m"
    }

    private func medalsSection(medals: [UserMedalResponse]) -> some View {
        VStack(spacing: .spacingSm) {
            HStack {
                Text("Medals")
                    .font(.headline)
                    .foregroundStyle(Color.tertiaryColor)
                Spacer()
                Text("\(medals.count)")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.4))
            }
            .padding(.horizontal, .spacingLg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .spacingMd) {
                    ForEach(medals, id: \.medal.id) { userMedal in
                        FriendMedalBadge(userMedal: userMedal)
                    }
                }
                .padding(.horizontal, .spacingLg)
            }
        }
    }

    private var presenceColor: Color {
        switch friend.presence {
        case .online:    return .green
        case .unplugged: return .orange
        case .offline:   return .gray
        }
    }

    private var presenceLabel: String {
        switch friend.presence {
        case .online:    return "Online"
        case .unplugged: return "Currently unplugged"
        case .offline:
            if let last = friend.lastActiveAt {
                return "Seen \(last.toRelativeTime())"
            }
            return "Offline"
        }
    }
}

private struct FriendMedalBadge: View {
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

#Preview {
    NavigationStack {
        FriendProfileView(friend: FriendResponse(
            id: UUID(),
            username: "alex",
            status: "accepted",
            presence: .online,
            hoursUnplugged: 12,
            lastActiveAt: Date()
        ))
        .environment(DependencyContainer())
    }
}
