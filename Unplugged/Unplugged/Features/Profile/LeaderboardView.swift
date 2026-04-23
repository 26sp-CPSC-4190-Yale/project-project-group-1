import SwiftUI
import UnpluggedShared

@MainActor
@Observable
final class LeaderboardViewModel {
    var entries: [LeaderboardEntryResponse] = []
    var isLoading = false
    var error: String?

    func load(service: FriendAPIService) async {
        isLoading = true
        error = nil
        do {
            entries = try await service.getLeaderboard()
        } catch is CancellationError {
        } catch {
            self.error = "Could not load leaderboard"
        }
        isLoading = false
    }
}

struct LeaderboardView: View {
    @Environment(DependencyContainer.self) private var deps
    @State private var viewModel = LeaderboardViewModel()

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: .spacingSm) {
                    if viewModel.entries.isEmpty && viewModel.isLoading {
                        ProgressView()
                            .tint(.tertiaryColor)
                            .padding(.top, 80)
                    } else if viewModel.entries.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.entries) { entry in
                            row(for: entry)
                        }
                    }
                }
                .padding(.horizontal, .spacingLg)
                .padding(.vertical, .spacingMd)
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await viewModel.load(service: deps.friends)
        }
        .refreshable {
            await viewModel.load(service: deps.friends)
        }
    }

    private var emptyState: some View {
        VStack(spacing: .spacingMd) {
            Image(systemName: "trophy")
                .font(.system(size: 48))
                .foregroundStyle(Color.tertiaryColor.opacity(0.3))
            Text(viewModel.error ?? "Add friends to see the leaderboard")
                .font(.subheadline)
                .foregroundStyle(Color.tertiaryColor.opacity(0.5))
        }
        .padding(.top, 80)
    }

    private func row(for entry: LeaderboardEntryResponse) -> some View {
        HStack(spacing: .spacingMd) {
            RankBadge(rank: entry.rank)

            ParticipantAvatar(name: entry.username, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.isCurrentUser ? "You" : entry.username)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.tertiaryColor)
                    if entry.isCurrentUser {
                        Text("(\(entry.username))")
                            .font(.caption)
                            .foregroundStyle(Color.tertiaryColor.opacity(0.5))
                    }
                }
                Text(subtitle(for: entry))
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
            }

            Spacer()

            Text("\(entry.hoursUnplugged)h")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.tertiaryColor)
        }
        .padding(.spacingMd)
        .background(
            RoundedRectangle(cornerRadius: .cornerRadius)
                .fill(Color.surfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: .cornerRadius)
                        .strokeBorder(
                            entry.isCurrentUser ? Color.secondaryColor.opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
    }

    private func subtitle(for entry: LeaderboardEntryResponse) -> String {
        let minutes = entry.minutesFocused
        if minutes < 60 { return "\(minutes) min focused" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours)h focused" }
        return "\(hours)h \(remainder)m focused"
    }
}

private struct RankBadge: View {
    let rank: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(background)
                .frame(width: 32, height: 32)
            Text("\(rank)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(foreground)
        }
    }

    private var background: Color {
        switch rank {
        case 1:  return Color.yellow.opacity(0.85)
        case 2:  return Color.gray.opacity(0.7)
        case 3:  return Color.orange.opacity(0.75)
        default: return Color.surfaceColor.opacity(0.4)
        }
    }

    private var foreground: Color {
        switch rank {
        case 1, 2, 3: return Color.primaryColor
        default:       return Color.tertiaryColor.opacity(0.7)
        }
    }
}

#Preview {
    NavigationStack {
        LeaderboardView()
            .environment(DependencyContainer())
    }
}
