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
        let howToUnlock: String
        let earned: @Sendable (UserStatsResponse) -> Bool
    }

    // medalName must match a row seeded by SeedMedals.
    // The howToUnlock strings are user-facing copy for the medal detail sheet.
    private static let rules: [Rule] = [
        Rule(medalName: "First Session",
             howToUnlock: "Finish your first unplugged session.",
             earned: { $0.totalSessions >= 1 }),
        Rule(medalName: "5 Sessions",
             howToUnlock: "Finish five unplugged sessions.",
             earned: { $0.totalSessions >= 5 }),
        Rule(medalName: "1 Hour Unplugged",
             howToUnlock: "Stay locked in for one hour in total.",
             earned: { $0.totalMinutes >= 60 }),
        Rule(medalName: "10 Hours Unplugged",
             howToUnlock: "Stay locked in for ten hours in total.",
             earned: { $0.totalMinutes >= 600 }),
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

    /// All medals in the catalog with the user's unlock status + how-to-unlock copy.
    /// Unlocked medals come first (most recent earnedAt first); then locked medals
    /// follow in catalog order.
    static func getCatalog(userID: UUID, on db: Database) async throws -> [MedalCatalogEntry] {
        let allMedals = try await MedalModel.query(on: db).all()
        let pivots = try await UserMedalPivot.query(on: db)
            .filter(\.$user.$id == userID)
            .all()
        var earnedByMedalID: [UUID: Date] = [:]
        for pivot in pivots {
            guard let earnedAt = pivot.earnedAt else { continue }
            earnedByMedalID[pivot.$medal.id] = earnedAt
        }

        let rulesByName = Dictionary(
            uniqueKeysWithValues: rules.map { ($0.medalName, $0.howToUnlock) }
        )

        let entries: [MedalCatalogEntry] = allMedals.compactMap { medal in
            guard let medalID = medal.id else { return nil }
            let response = MedalResponse(
                id: medalID,
                name: medal.name,
                description: medal.description,
                icon: medal.icon
            )
            let howToUnlock = rulesByName[medal.name] ?? medal.description
            return MedalCatalogEntry(
                medal: response,
                earnedAt: earnedByMedalID[medalID],
                howToUnlock: howToUnlock
            )
        }

        // Sort: unlocked first (newest earned first), then locked in catalog order.
        return entries.sorted { lhs, rhs in
            switch (lhs.earnedAt, rhs.earnedAt) {
            case let (l?, r?): return l > r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return lhs.medal.name < rhs.medal.name
            }
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
