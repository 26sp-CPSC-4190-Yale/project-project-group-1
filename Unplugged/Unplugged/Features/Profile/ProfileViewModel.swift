//
//  ProfileViewModel.swift
//  Unplugged.Features.Profile
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

// TODO: Replace hardcoded stats with UserAPIService.getStats(); fetch real user data on appear

import Foundation
import Observation

@MainActor
@Observable
class ProfileViewModel {
    var selectedTab: ProfileTab = .history

    let userName = "Sebastian"
    let hoursUnplugged = 32
    let rank = "1st"
    let totalSessions = 4
    let longestStreak = 5
    let friendsCount = 12
    let avgSessionLength = "1.5"
    let currentStreak = 3

    enum ProfileTab: String, CaseIterable, Identifiable {
        case history = "History"
        case settings = "Settings"
        var id: String { rawValue }
    }
}
