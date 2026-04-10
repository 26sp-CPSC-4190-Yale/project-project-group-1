//
//  StatsService.swift
//  UnpluggedServer.Services
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
import Foundation
import UnpluggedShared
import Vapor

struct StatsService {
    static func getStats(for userID: UUID, on db: Database) async throws -> UserStatsResponse {
        // All memberships for this user
        let memberships = try await MemberModel.query(on: db)
            .filter(\.$userID == userID)
            .all()
        let roomIDs = memberships.map { $0.roomID }

        // Only ended rooms count for stats
        let endedRooms: [RoomModel]
        if roomIDs.isEmpty {
            endedRooms = []
        } else {
            endedRooms = try await RoomModel.query(on: db)
                .filter(\.$id ~~ roomIDs)
                .filter(\.$endedAt != nil)
                .all()
        }

        let totalSessions = endedRooms.count
        let totalMinutes = endedRooms.reduce(0) { acc, room in
            acc + ((room.durationSeconds ?? 0) / 60)
        }
        let avgSessionLengthMinutes: Double = totalSessions > 0
            ? Double(totalMinutes) / Double(totalSessions)
            : 0

        // Streaks — distinct days with an ended session, sorted descending
        let calendar = Calendar(identifier: .gregorian)
        let sessionDays: Set<Date> = Set(endedRooms.compactMap { room in
            guard let ended = room.endedAt else { return nil }
            return calendar.startOfDay(for: ended)
        })
        let sortedDays = sessionDays.sorted()

        var longestStreak = 0
        var currentRun = 0
        var previousDay: Date?
        for day in sortedDays {
            if let prev = previousDay,
               let diff = calendar.dateComponents([.day], from: prev, to: day).day,
               diff == 1 {
                currentRun += 1
            } else {
                currentRun = 1
            }
            longestStreak = max(longestStreak, currentRun)
            previousDay = day
        }

        // Current streak: consecutive days ending today or yesterday
        var currentStreak = 0
        let today = calendar.startOfDay(for: Date())
        var cursor = today
        while sessionDays.contains(cursor) {
            currentStreak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        if currentStreak == 0 {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            var alt = yesterday
            while sessionDays.contains(alt) {
                currentStreak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: alt) else { break }
                alt = prev
            }
        }

        // Friends count (accepted only)
        let friendCount = try await FriendshipModel.query(on: db)
            .group(.or) { group in
                group.group(.and) { g in
                    g.filter(\.$user1ID == userID)
                    g.filter(\.$status == "accepted")
                }
                group.group(.and) { g in
                    g.filter(\.$user2ID == userID)
                    g.filter(\.$status == "accepted")
                }
            }
            .count()

        // Rank — global position by totalMinutes
        let rank = try await computeRank(for: userID, totalMinutes: totalMinutes, on: db)

        return UserStatsResponse(
            hoursUnplugged: totalMinutes / 60,
            rank: rank,
            totalSessions: totalSessions,
            longestStreak: longestStreak,
            currentStreak: currentStreak,
            avgSessionLengthMinutes: avgSessionLengthMinutes,
            friendsCount: friendCount,
            totalMinutes: totalMinutes
        )
    }

    /// Compute a user's rank among all users by total minutes unplugged.
    private static func computeRank(for userID: UUID, totalMinutes: Int, on db: Database) async throws -> Int {
        let allUsers = try await UserModel.query(on: db).all()
        var totals: [(UUID, Int)] = []
        for user in allUsers {
            guard let uid = user.id else { continue }
            let memberships = try await MemberModel.query(on: db)
                .filter(\.$userID == uid)
                .all()
            let roomIDs = memberships.map { $0.roomID }
            guard !roomIDs.isEmpty else {
                totals.append((uid, 0))
                continue
            }
            let rooms = try await RoomModel.query(on: db)
                .filter(\.$id ~~ roomIDs)
                .filter(\.$endedAt != nil)
                .all()
            let minutes = rooms.reduce(0) { $0 + (($1.durationSeconds ?? 0) / 60) }
            totals.append((uid, minutes))
        }
        let sorted = totals.sorted { $0.1 > $1.1 }
        if let idx = sorted.firstIndex(where: { $0.0 == userID }) {
            return idx + 1
        }
        return sorted.count
    }
}
