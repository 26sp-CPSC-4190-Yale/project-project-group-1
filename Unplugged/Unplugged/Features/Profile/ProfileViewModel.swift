//
//  ProfileViewModel.swift
//  Unplugged.Features.Profile
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class ProfileViewModel {
    var userName: String = ""
    var stats: UserStatsResponse?
    var isLoading = false
    var error: String?
    var isShowingEmergencyAppsSheet = false

    // Account deletion
    var isShowingDeleteAccountSheet = false
    var isDeletingAccount = false
    var deleteAccountError: String?

    // Computed display-friendly values — empty until stats load.
    var hoursUnplugged: Int { stats?.hoursUnplugged ?? 0 }
    var rank: String {
        guard let r = stats?.rank, r > 0 else { return "–" }
        return "\(r)\(Self.ordinalSuffix(for: r))"
    }
    var totalSessions: Int { stats?.totalSessions ?? 0 }
    var longestStreak: Int { stats?.longestStreak ?? 0 }
    var friendsCount: Int { stats?.friendsCount ?? 0 }
    var currentStreak: Int { stats?.currentStreak ?? 0 }
    var avgSessionLength: String {
        guard let mins = stats?.avgSessionLengthMinutes, mins > 0 else { return "0" }
        let hours = mins / 60
        return String(format: "%.1f", hours)
    }

    func load(stats service: StatsAPIService, cache: LocalCacheService) async {
        if let cachedUser = cache.readUser() {
            userName = cachedUser.username
        }
        // Start with any cached stats to avoid a blank render.
        if stats == nil, let cached = cache.readStats() {
            stats = cached
        }
        isLoading = true
        error = nil
        do {
            let fresh = try await service.getMyStats()
            stats = fresh
            cache.saveStats(fresh)
        } catch {
            self.error = "Could not load stats"
        }
        isLoading = false
    }

    /// Soft-deletes the account via the server, then signs out on success.
    /// On failure, surfaces the error in-sheet and leaves the user signed in.
    func deleteAccount(password: String?, user: UserAPIService, auth: AuthViewModel) async {
        isDeletingAccount = true
        deleteAccountError = nil
        do {
            try await user.deleteAccount(password: password)
            isShowingDeleteAccountSheet = false
            auth.signOut()
        } catch let err as NSError where err.code == 401 {
            deleteAccountError = "Incorrect password."
        } catch let err as NSError where err.code == 400 {
            deleteAccountError = "Password required."
        } catch {
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
