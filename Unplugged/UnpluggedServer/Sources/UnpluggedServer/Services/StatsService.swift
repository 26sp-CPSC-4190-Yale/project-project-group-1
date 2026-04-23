import Fluent
import Foundation
import UnpluggedShared
import Vapor

struct StatsService {
    // absorbs sub-second drift between client clocks and server Date(), so a clean run is not flagged as early
    static let earlyLeaveToleranceSeconds: Int = 5

    static func getStats(for userID: UUID, on db: Database) async throws -> UserStatsResponse {
        let memberships = try await MemberModel.query(on: db)
            .filter(\.$userID == userID)
            .all()
        let roomIDs = memberships.map { $0.roomID }

        let endedRooms: [RoomModel]
        if roomIDs.isEmpty {
            endedRooms = []
        } else {
            endedRooms = try await RoomModel.query(on: db)
                .filter(\.$id ~~ roomIDs)
                .filter(\.$endedAt != nil)
                .all()
        }

        let endedRoomIDs = endedRooms.compactMap { try? $0.requireID() }
        let jailbreaks: [JailbreakModel]
        if endedRoomIDs.isEmpty {
            jailbreaks = []
        } else {
            jailbreaks = try await JailbreakModel.query(on: db)
                .filter(\.$userID == userID)
                .filter(\.$sessionID ~~ endedRoomIDs)
                .all()
        }
        var earliestLeave: [UUID: Date] = [:]
        for jb in jailbreaks {
            if let prev = earliestLeave[jb.sessionID], prev <= jb.detectedAt { continue }
            earliestLeave[jb.sessionID] = jb.detectedAt
        }

        let totalSessions = endedRooms.count
        var focusedSeconds = 0
        var plannedSeconds = 0
        var earlyLeaveCount = 0

        for room in endedRooms {
            let planned = max(0, room.durationSeconds ?? 0)
            plannedSeconds += planned

            let focused = Self.focusedSeconds(
                room: room,
                earliestLeaveAt: room.id.flatMap { earliestLeave[$0] }
            )
            focusedSeconds += focused
            if focused + earlyLeaveToleranceSeconds < planned {
                earlyLeaveCount += 1
            }
        }

        let totalMinutes = focusedSeconds / 60
        let avgSessionLengthMinutes: Double = totalSessions > 0
            ? Double(focusedSeconds) / Double(totalSessions) / 60.0
            : 0
        let plannedMinutes = plannedSeconds / 60
        let avgPlannedMinutes: Double = totalSessions > 0
            ? Double(plannedSeconds) / Double(totalSessions) / 60.0
            : 0

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

        // walks from today then retries from yesterday so a streak that has not been extended yet today still counts
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

        // scope is accepted friends plus self, must match FriendController.leaderboard so rank and leaderboard agree
        let friendships = try await FriendshipModel.query(on: db)
            .filter(\.$status == "accepted")
            .group(.or) { group in
                group.filter(\.$user1ID == userID)
                group.filter(\.$user2ID == userID)
            }
            .all()
        let friendCount = friendships.count

        let hiddenIDs = try await BlockService.hiddenUserIDs(for: userID, on: db)
        var rankScope: Set<UUID> = [userID]
        for f in friendships {
            let other = f.user1ID == userID ? f.user2ID : f.user1ID
            if !hiddenIDs.contains(other) {
                rankScope.insert(other)
            }
        }
        let rank = try await computeRank(
            for: userID,
            focusedMinutes: totalMinutes,
            scopeIDs: rankScope,
            on: db
        )

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
            plannedMinutes: plannedMinutes,
            avgPlannedMinutes: avgPlannedMinutes,
            earlyLeaveCount: earlyLeaveCount,
            points: user?.points ?? 0
        )
    }

    // earliest jailbreak wins as the exit anchor, result is clamped into [0, planned] to absorb clock drift and overrun
    static func focusedSeconds(room: RoomModel, earliestLeaveAt: Date?) -> Int {
        guard let lockedAt = room.lockedAt else { return 0 }
        let planned = max(0, room.durationSeconds ?? 0)
        let endAnchor: Date
        if let leave = earliestLeaveAt {
            endAnchor = min(leave, room.endedAt ?? leave)
        } else {
            endAnchor = room.endedAt ?? lockedAt
        }
        let elapsed = Int(endAnchor.timeIntervalSince(lockedAt).rounded())
        return max(0, min(elapsed, planned))
    }

    // ties share the same rank, matching buildLeaderboard's behavior
    private static func computeRank(
        for userID: UUID,
        focusedMinutes: Int,
        scopeIDs: Set<UUID>,
        on db: Database
    ) async throws -> Int {
        guard !scopeIDs.isEmpty else { return 1 }
        let scopeArray = Array(scopeIDs)

        let allEndedRooms = try await RoomModel.query(on: db)
            .filter(\.$endedAt != nil)
            .all()
        let endedRoomIDs = allEndedRooms.compactMap { try? $0.requireID() }
        guard !endedRoomIDs.isEmpty else { return 1 }

        let allMemberships = try await MemberModel.query(on: db)
            .filter(\.$roomID ~~ endedRoomIDs)
            .filter(\.$userID ~~ scopeArray)
            .all()
        let allJailbreaks = try await JailbreakModel.query(on: db)
            .filter(\.$sessionID ~~ endedRoomIDs)
            .filter(\.$userID ~~ scopeArray)
            .all()

        var leaveMap: [UUID: [UUID: Date]] = [:]
        for jb in allJailbreaks {
            var byRoom = leaveMap[jb.userID] ?? [:]
            if let prev = byRoom[jb.sessionID], prev <= jb.detectedAt {
                continue
            }
            byRoom[jb.sessionID] = jb.detectedAt
            leaveMap[jb.userID] = byRoom
        }

        var roomsByID: [UUID: RoomModel] = [:]
        for room in allEndedRooms {
            if let id = room.id { roomsByID[id] = room }
        }

        // seed every scoped user at 0 so users with no ended rooms still appear in the ranking
        var userMinutes: [UUID: Int] = Dictionary(uniqueKeysWithValues: scopeIDs.map { ($0, 0) })
        for member in allMemberships {
            guard let room = roomsByID[member.roomID] else { continue }
            let leave = leaveMap[member.userID]?[member.roomID]
            let focused = focusedSeconds(room: room, earliestLeaveAt: leave)
            userMinutes[member.userID, default: 0] += focused / 60
        }
        // pin the caller's total to the already-computed figure so this recomputation cannot drift from the caller's
        userMinutes[userID] = focusedMinutes

        let allTotals = userMinutes.values.sorted(by: >)
        var rank = 1
        for val in allTotals {
            if val > focusedMinutes {
                rank += 1
            } else {
                break
            }
        }
        return rank
    }

    static func buildLeaderboard(
        userIDs: [UUID],
        currentUserID: UUID,
        on db: Database
    ) async throws -> [LeaderboardEntryResponse] {
        guard !userIDs.isEmpty else { return [] }

        let users = try await UserModel.query(on: db)
            .filter(\.$id ~~ userIDs)
            .all()
        let usernames = Dictionary(uniqueKeysWithValues: users.compactMap { u -> (UUID, String)? in
            guard let id = u.id else { return nil }
            return (id, u.username)
        })

        var focusedByUser: [UUID: Int] = [:]
        for userID in userIDs {
            let stats = try await getStats(for: userID, on: db)
            focusedByUser[userID] = stats.totalMinutes
        }

        let sorted = focusedByUser
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                let lhsName = usernames[lhs.key] ?? ""
                let rhsName = usernames[rhs.key] ?? ""
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }

        var entries: [LeaderboardEntryResponse] = []
        var rank = 0
        var previousValue: Int? = nil
        var position = 0
        for (uid, minutes) in sorted {
            position += 1
            if minutes != previousValue {
                rank = position
                previousValue = minutes
            }
            entries.append(
                LeaderboardEntryResponse(
                    id: uid,
                    username: usernames[uid] ?? "unknown",
                    hoursUnplugged: minutes / 60,
                    minutesFocused: minutes,
                    rank: rank,
                    isCurrentUser: uid == currentUserID
                )
            )
        }
        return entries
    }
}
