//
//  StatsService.swift
//  UnpluggedServer.Services
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

        let user = try await UserModel.find(userID, on: db)

        return UserStatsResponse(
            hoursUnplugged: totalMinutes / 60,
            rank: rank,
            totalSessions: totalSessions,
            longestStreak: longestStreak,
            currentStreak: currentStreak,
            avgSessionLengthMinutes: avgSessionLengthMinutes,
            friendsCount: friendCount,
            totalMinutes: totalMinutes,
            points: user?.points ?? 0
        )
    }

    /// Compute a user's rank among all users by total minutes unplugged.
    private static func computeRank(for userID: UUID, totalMinutes: Int, on db: Database) async throws -> Int {
        let allMemberships = try await MemberModel.query(on: db).all()
        let allEndedRooms = try await RoomModel.query(on: db)
            .filter(\.$endedAt != nil)
            .all()

        var roomDurations: [UUID: Int] = [:]
        for room in allEndedRooms {
            guard let id = room.id else { continue }
            roomDurations[id] = (room.durationSeconds ?? 0) / 60
        }

        var userTotals: [UUID: Int] = [:]
        for member in allMemberships {
            let mins = roomDurations[member.roomID] ?? 0
            userTotals[member.userID, default: 0] += mins
        }

        let allTotals = userTotals.values.sorted(by: >)
        var rank = 1
        for val in allTotals {
            if val > totalMinutes {
                rank += 1
            } else {
                break
            }
        }
        return rank
    }
}
