//
//  MedalService.swift
//  UnpluggedServer.Services
//

import Fluent
import Foundation
import UnpluggedShared
import Vapor

struct MedalService {
    private struct Rule: Sendable {
        let medalName: String
        let earned: @Sendable (UserStatsResponse) -> Bool
    }

    // medalName must match a row seeded by SeedMedals.
    private static let rules: [Rule] = [
        Rule(medalName: "First Session", earned: { $0.totalSessions >= 1 }),
        Rule(medalName: "5 Sessions", earned: { $0.totalSessions >= 5 }),
        Rule(medalName: "1 Hour Unplugged", earned: { $0.totalMinutes >= 60 }),
        Rule(medalName: "10 Hours Unplugged", earned: { $0.totalMinutes >= 600 }),
    ]

    // Non-throwing: medal failures must not break session end.
    static func evaluateAndAward(userID: UUID, on db: Database, logger: Logger) async {
        do {
            let stats = try await StatsService.getStats(for: userID, on: db)
            for rule in rules where rule.earned(stats) {
                await awardIfEligible(userID: userID, medalName: rule.medalName, on: db, logger: logger)
            }
        } catch {
            logger.warning("MedalService.evaluateAndAward failed", metadata: [
                "user_id": "\(userID)",
                "error": "\(error)"
            ])
        }
    }

    static func getUserMedals(userID: UUID, on db: Database) async throws -> [UserMedalResponse] {
        let pivots = try await UserMedalPivot.query(on: db)
            .filter(\.$user.$id == userID)
            .with(\.$medal)
            .sort(\.$earnedAt, .descending)
            .all()
        return pivots.compactMap { pivot in
            guard let earnedAt = pivot.earnedAt,
                  let medalID = pivot.medal.id else { return nil }
            let medal = pivot.medal
            return UserMedalResponse(
                medal: MedalResponse(
                    id: medalID,
                    name: medal.name,
                    description: medal.description,
                    icon: medal.icon
                ),
                earnedAt: earnedAt
            )
        }
    }

    private static func awardIfEligible(userID: UUID, medalName: String, on db: Database, logger: Logger) async {
        do {
            guard let medal = try await MedalModel.query(on: db)
                .filter(\.$name == medalName)
                .first(),
                  let medalID = medal.id
            else {
                logger.warning("MedalService: medal row missing; did the SeedMedals migration run?", metadata: [
                    "medal_name": "\(medalName)"
                ])
                return
            }

            let existing = try await UserMedalPivot.query(on: db)
                .filter(\.$user.$id == userID)
                .filter(\.$medal.$id == medalID)
                .first()
            guard existing == nil else { return }

            let pivot = UserMedalPivot(userID: userID, medalID: medalID)
            try await pivot.save(on: db)
        } catch {
            logger.warning("MedalService: award failed", metadata: [
                "user_id": "\(userID)",
                "medal_name": "\(medalName)",
                "error": "\(error)"
            ])
        }
    }
}
