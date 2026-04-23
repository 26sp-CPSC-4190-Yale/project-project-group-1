import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class ProfileViewModel {
    var userName: String = ""
    var stats: UserStatsResponse?
    var medals: [UserMedalResponse] = []
    var isLoading = false
    var error: String?
    var isShowingEmergencyAppsSheet = false

    var isShowingDeleteAccountSheet = false
    var isDeletingAccount = false
    var deleteAccountError: String?

    var hoursUnplugged: Int { stats?.hoursUnplugged ?? 0 }
    var rank: String {
        guard let r = stats?.rank, r > 0 else { return "–" }
        return "\(r)\(Self.ordinalSuffix(for: r))"
    }
    var totalSessions: Int { stats?.totalSessions ?? 0 }
    var longestStreak: Int { stats?.longestStreak ?? 0 }
    var friendsCount: Int { stats?.friendsCount ?? 0 }
    var currentStreak: Int { stats?.currentStreak ?? 0 }
    var earlyLeaveCount: Int { stats?.earlyLeaveCount ?? 0 }

    var avgFocusedSessionLabel: String {
        guard let mins = stats?.avgSessionLengthMinutes, mins > 0 else { return "0m" }
        if mins >= 60 {
            return String(format: "%.1fh", mins / 60.0)
        }
        return "\(Int(mins.rounded()))m"
    }

    var avgPlannedSessionLabel: String {
        guard let mins = stats?.avgPlannedMinutes, mins > 0 else { return "0m" }
        if mins >= 60 {
            return String(format: "%.1fh", mins / 60.0)
        }
        return "\(Int(mins.rounded()))m"
    }

    var avgSessionLength: String { avgFocusedSessionLabel }

    func load(stats service: StatsAPIService, medals medalsService: MedalsAPIService, cache: LocalCacheService) async {
        if let cachedUser = cache.readUser() {
            userName = cachedUser.username
        }
        if stats == nil, let cached = cache.readStats() {
            stats = cached
        }
        isLoading = true
        error = nil
        async let freshStats = service.getMyStats()
        async let freshMedals = medalsService.getMyMedals()
        do {
            let (s, m) = try await (freshStats, freshMedals)
            stats = s
            cache.saveStats(s)
            medals = m
        } catch {
            AppLogger.profile.error("profile stats/medals fetch failed", error: error)
            self.error = "Could not load stats"
        }
        isLoading = false
    }

    func deleteAccount(password: String?, user: UserAPIService, auth: AuthViewModel) async {
        isDeletingAccount = true
        deleteAccountError = nil
        do {
            try await user.deleteAccount(password: password)
            isShowingDeleteAccountSheet = false
            auth.signOut()
        } catch let err as NSError where err.code == 401 {
            AppLogger.profile.warning("deleteAccount 401 — incorrect password")
            deleteAccountError = "Incorrect password."
        } catch let err as NSError where err.code == 400 {
            AppLogger.profile.warning("deleteAccount 400 — password required")
            deleteAccountError = "Password required."
        } catch {
            AppLogger.profile.error("deleteAccount failed", error: error)
            deleteAccountError = "Couldn't delete account. Try again."
        }
        isDeletingAccount = false
    }

    enum ProfileTab: String, CaseIterable, Identifiable {
        case history = "History"
        case settings = "Settings"
        var id: String { rawValue }
    }

    private static func ordinalSuffix(for n: Int) -> String {
        let mod100 = n % 100
        if (11...13).contains(mod100) { return "th" }
        switch n % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
