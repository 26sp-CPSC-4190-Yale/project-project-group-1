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
        let sessionIDs = memberships.map { $0.sessionID }

        let endedSessions: [SessionModel]
        if sessionIDs.isEmpty {
            endedSessions = []
        } else {
            endedSessions = try await SessionModel.query(on: db)
                .filter(\.$id ~~ sessionIDs)
                .filter(\.$endedAt != nil)
                .all()
        }

        let endedSessionIDs = endedSessions.compactMap { try? $0.requireID() }
        let jailbreaks: [JailbreakModel]
        if endedSessionIDs.isEmpty {
            jailbreaks = []
        } else {
            jailbreaks = try await JailbreakModel.query(on: db)
                .filter(\.$userID == userID)
                .filter(\.$sessionID ~~ endedSessionIDs)
                .all()
        }
        var earliestLeave: [UUID: Date] = [:]
        for jb in jailbreaks {
            if let prev = earliestLeave[jb.sessionID], prev <= jb.detectedAt { continue }
            earliestLeave[jb.sessionID] = jb.detectedAt
        }

        let totalSessions = endedSessions.count
        var focusedSeconds = 0
        var plannedSeconds = 0
        var earlyLeaveCount = 0

        for session in endedSessions {
            let planned = max(0, session.durationSeconds ?? 0)
            plannedSeconds += planned

            let focused = Self.focusedSeconds(
                session: session,
                earliestLeaveAt: session.id.flatMap { earliestLeave[$0] }
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
        let sessionDays: Set<Date> = Set(endedSessions.compactMap { session in
            guard let ended = session.endedAt else { return nil }
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
        let user = try await UserModel.find(userID, on: db)

        let rank = try await computeRank(
            for: userID,
            points: user?.points ?? 0,
            scopeIDs: rankScope,
            on: db
        )

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

    // earliest jailbreak wins as the exit anchor; finite sessions clamp to planned duration, unlimited sessions report elapsed time.
    static func focusedSeconds(session: SessionModel, earliestLeaveAt: Date?) -> Int {
        guard let lockedAt = session.lockedAt else { return 0 }
        let planned = session.durationSeconds.map { max(0, $0) }
        let endAnchor: Date
        if let leave = earliestLeaveAt {
            endAnchor = min(leave, session.endedAt ?? leave)
        } else {
            endAnchor = session.endedAt ?? lockedAt
        }
        let rawElapsed = endAnchor.timeIntervalSince(lockedAt)
        let elapsed = rawElapsed > 0 ? max(1, Int(rawElapsed.rounded())) : 0
        guard let planned else { return elapsed }
        return min(elapsed, planned)
    }

    // ties share the same rank, matching buildLeaderboard's behavior
    private static func computeRank(
        for userID: UUID,
        points: Int,
        scopeIDs: Set<UUID>,
        on db: Database
    ) async throws -> Int {
        guard !scopeIDs.isEmpty else { return 1 }
        let users = try await UserModel.query(on: db)
            .filter(\.$id ~~ Array(scopeIDs))
            .all()
        var rank = 1
        for user in users {
            guard let uid = user.id, uid != userID else { continue }
            if user.points > points { rank += 1 }
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
            .filter(\.$deletedAt == nil)
            .all()
        let usernames = Dictionary(uniqueKeysWithValues: users.compactMap { u -> (UUID, String)? in
            guard let id = u.id else { return nil }
            return (id, u.username)
        })
        let pointsByUser = Dictionary(uniqueKeysWithValues: users.compactMap { u -> (UUID, Int)? in
            guard let id = u.id else { return nil }
            return (id, u.points)
        })

        let visibleUserIDs = Array(usernames.keys)
        let focusedByUser = try await focusedMinutesByUser(visibleUserIDs, on: db)

        let sorted = visibleUserIDs
            .sorted { lhs, rhs in
                let lhsPts = pointsByUser[lhs] ?? 0
                let rhsPts = pointsByUser[rhs] ?? 0
                if lhsPts != rhsPts { return lhsPts > rhsPts }
                let lhsName = usernames[lhs] ?? ""
                let rhsName = usernames[rhs] ?? ""
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }

        var entries: [LeaderboardEntryResponse] = []
        var rank = 0
        var previousValue: Int? = nil
        var position = 0
        for uid in sorted {
            let pts = pointsByUser[uid] ?? 0
            let minutes = focusedByUser[uid] ?? 0
            position += 1
            if pts != previousValue {
                rank = position
                previousValue = pts
            }
            entries.append(
                LeaderboardEntryResponse(
                    id: uid,
                    username: usernames[uid] ?? "unknown",
                    hoursUnplugged: minutes / 60,
                    minutesFocused: minutes,
                    rank: rank,
                    isCurrentUser: uid == currentUserID,
                    points: pts
                )
            )
        }
        return entries
    }

    private static func focusedMinutesByUser(_ userIDs: [UUID], on db: Database) async throws -> [UUID: Int] {
        let scopeIDs = Set(userIDs)
        guard !scopeIDs.isEmpty else { return [:] }

        let endedSessions = try await SessionModel.query(on: db)
            .filter(\.$endedAt != nil)
            .all()
        let endedSessionIDs = endedSessions.compactMap { try? $0.requireID() }
        guard !endedSessionIDs.isEmpty else {
            return Dictionary(uniqueKeysWithValues: scopeIDs.map { ($0, 0) })
        }

        let memberships = try await MemberModel.query(on: db)
            .filter(\.$sessionID ~~ endedSessionIDs)
            .filter(\.$userID ~~ Array(scopeIDs))
            .all()
        let jailbreaks = try await JailbreakModel.query(on: db)
            .filter(\.$sessionID ~~ endedSessionIDs)
            .filter(\.$userID ~~ Array(scopeIDs))
            .all()

        var earliestLeave: [UUID: [UUID: Date]] = [:]
        for jailbreak in jailbreaks {
            var bySession = earliestLeave[jailbreak.userID] ?? [:]
            if let previous = bySession[jailbreak.sessionID], previous <= jailbreak.detectedAt {
                continue
            }
            bySession[jailbreak.sessionID] = jailbreak.detectedAt
            earliestLeave[jailbreak.userID] = bySession
        }

        let sessionsByID = Dictionary(uniqueKeysWithValues: endedSessions.compactMap { session -> (UUID, SessionModel)? in
            guard let id = session.id else { return nil }
            return (id, session)
        })

        var minutes = Dictionary(uniqueKeysWithValues: scopeIDs.map { ($0, 0) })
        for member in memberships {
            guard let session = sessionsByID[member.sessionID] else { continue }
            let focused = focusedSeconds(
                session: session,
                earliestLeaveAt: earliestLeave[member.userID]?[member.sessionID]
            )
            minutes[member.userID, default: 0] += focused / 60
        }
        return minutes
    }
}
