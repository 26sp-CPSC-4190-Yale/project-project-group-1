//
//  StatsService.swift
//  UnpluggedServer.Services
//

import Fluent
import Foundation
import UnpluggedShared

struct StatsService {
    let db: Database

    func getStats(for userID: UUID) async throws -> UserStatsResponse {
        let memberships = try await MemberModel.query(on: db)
            .filter(\.$userID == userID)
            .all()

        let roomIDs = memberships.map { $0.roomID }
        let roomMap: [UUID: RoomModel]
        if roomIDs.isEmpty {
            roomMap = [:]
        } else {
            let roomList = try await RoomModel.query(on: db)
                .filter(\.$id ~~ roomIDs)
                .all()
            roomMap = Dictionary(uniqueKeysWithValues: roomList.compactMap { r -> (UUID, RoomModel)? in
                guard let id = r.id else { return nil }
                return (id, r)
            })
        }

        var totalMinutes = 0
        var completedSessions = 0

        for member in memberships {
            let room = roomMap[member.roomID]

            // Only count settled participation, so the user has left, or the
            // session has ended. Active-session time is excluded so stats
            // don't drift on every read.
            if let endTime = member.leftAt ?? room?.endedAt {
                let minutes = Int(endTime.timeIntervalSince(member.joinedAt) / 60)
                totalMinutes += max(0, minutes)
            }

            // Completed: session ended and user did not leave early
            if room?.isActive == false && !member.leftEarly {
                completedSessions += 1
            }
        }

        let jailbreakCount = try await JailbreakModel.query(on: db)
            .filter(\.$userID == userID)
            .count()

        let user = try await UserModel.find(userID, on: db)

        return UserStatsResponse(
            totalSessions: memberships.count,
            completedSessions: completedSessions,
            totalMinutes: totalMinutes,
            jailbreakCount: jailbreakCount,
            points: user?.points ?? 0
        )
    }
}
