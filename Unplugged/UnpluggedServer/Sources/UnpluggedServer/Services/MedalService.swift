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

    // catalog-only, eligibility depends on per-session friend overlap so it cannot be expressed against UserStatsResponse
    private struct SocialRule: Sendable {
        let medalName: String
        let howToUnlock: String
    }

    // medalName must match a row seeded by SeedMedals or SeedMoreMedals
    private static let rules: [Rule] = [
        Rule(medalName: "First Session",
             howToUnlock: "Finish your first unplugged session.",
             earned: { $0.totalSessions >= 1 }),
        Rule(medalName: "5 Sessions",
             howToUnlock: "Finish five unplugged sessions.",
             earned: { $0.totalSessions >= 5 }),
        Rule(medalName: "25 Sessions",
             howToUnlock: "Finish twenty-five unplugged sessions.",
             earned: { $0.totalSessions >= 25 }),
        Rule(medalName: "50 Sessions",
             howToUnlock: "Finish fifty unplugged sessions.",
             earned: { $0.totalSessions >= 50 }),
        Rule(medalName: "100 Sessions",
             howToUnlock: "Finish one hundred unplugged sessions.",
             earned: { $0.totalSessions >= 100 }),

        Rule(medalName: "1 Hour Unplugged",
             howToUnlock: "Stay locked in for one hour in total.",
             earned: { $0.totalMinutes >= 60 }),
        Rule(medalName: "5 Hours Unplugged",
             howToUnlock: "Stay locked in for five hours in total.",
             earned: { $0.totalMinutes >= 300 }),
        Rule(medalName: "10 Hours Unplugged",
             howToUnlock: "Stay locked in for ten hours in total.",
             earned: { $0.totalMinutes >= 600 }),
        Rule(medalName: "50 Hours Unplugged",
             howToUnlock: "Stay locked in for fifty hours in total.",
             earned: { $0.totalMinutes >= 3_000 }),
        Rule(medalName: "100 Hours Unplugged",
             howToUnlock: "Stay locked in for one hundred hours in total.",
             earned: { $0.totalMinutes >= 6_000 }),

        // checked against longestStreak so a missed day does not revoke a previously earned medal
        Rule(medalName: "3-Day Streak",
             howToUnlock: "Complete a session on three days in a row.",
             earned: { $0.longestStreak >= 3 }),
        Rule(medalName: "7-Day Streak",
             howToUnlock: "Complete a session on seven days in a row.",
             earned: { $0.longestStreak >= 7 }),
        Rule(medalName: "30-Day Streak",
             howToUnlock: "Complete a session on thirty days in a row.",
             earned: { $0.longestStreak >= 30 }),

        Rule(medalName: "First Friend",
             howToUnlock: "Add your first friend.",
             earned: { $0.friendsCount >= 1 }),
        Rule(medalName: "Social Circle",
             howToUnlock: "Reach five friends.",
             earned: { $0.friendsCount >= 5 }),
        Rule(medalName: "Popular",
             howToUnlock: "Reach ten friends.",
             earned: { $0.friendsCount >= 10 }),

        // earlyLeaveCount counts both voluntary exits and jailbreak-shortened sessions, defined in StatsService
        Rule(medalName: "Slip-Up",
             howToUnlock: "Leave a session before it ends.",
             earned: { $0.earlyLeaveCount >= 1 }),
        Rule(medalName: "Weak Willed",
             howToUnlock: "Leave early five times.",
             earned: { $0.earlyLeaveCount >= 5 }),
        Rule(medalName: "Hall of Shame",
             howToUnlock: "Leave early ten times.",
             earned: { $0.earlyLeaveCount >= 10 }),
    ]

    private static let socialRules: [SocialRule] = [
        SocialRule(medalName: "Better Together",
                   howToUnlock: "Finish a session with at least one friend."),
        SocialRule(medalName: "Squad Up",
                   howToUnlock: "Finish a session with three or more friends."),
    ]

    // never throws, medal failures must not prevent session end from completing
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

        await evaluateSocialMedals(userID: userID, on: db, logger: logger)
    }

    private static func evaluateSocialMedals(userID: UUID, on db: Database, logger: Logger) async {
        do {
            let friendships = try await FriendshipModel.query(on: db)
                .filter(\.$status == "accepted")
                .group(.or) { group in
                    group.filter(\.$user1ID == userID)
                    group.filter(\.$user2ID == userID)
                }
                .all()
            let friendIDs: Set<UUID> = Set(friendships.map { $0.user1ID == userID ? $0.user2ID : $0.user1ID })
            guard !friendIDs.isEmpty else { return }

            let myMemberships = try await MemberModel.query(on: db)
                .filter(\.$userID == userID)
                .all()
            let myRoomIDs = myMemberships.map { $0.roomID }
            guard !myRoomIDs.isEmpty else { return }

            let endedRoomIDs: [UUID] = try await RoomModel.query(on: db)
                .filter(\.$id ~~ myRoomIDs)
                .filter(\.$endedAt != nil)
                .all()
                .compactMap { try? $0.requireID() }
            guard !endedRoomIDs.isEmpty else { return }

            let allMembers = try await MemberModel.query(on: db)
                .filter(\.$roomID ~~ endedRoomIDs)
                .all()

            var friendCountByRoom: [UUID: Int] = [:]
            for member in allMembers where member.userID != userID {
                if friendIDs.contains(member.userID) {
                    friendCountByRoom[member.roomID, default: 0] += 1
                }
            }

            let maxFriendsInAnySession = friendCountByRoom.values.max() ?? 0

            if maxFriendsInAnySession >= 1 {
                await awardIfEligible(userID: userID, medalName: "Better Together", on: db, logger: logger)
            }
            if maxFriendsInAnySession >= 3 {
                await awardIfEligible(userID: userID, medalName: "Squad Up", on: db, logger: logger)
            }
        } catch {
            logger.warning("MedalService.evaluateSocialMedals failed", metadata: [
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

        var howToUnlockByName: [String: String] = Dictionary(
            uniqueKeysWithValues: rules.map { ($0.medalName, $0.howToUnlock) }
        )
        for social in socialRules {
            howToUnlockByName[social.medalName] = social.howToUnlock
        }

        let entries: [MedalCatalogEntry] = allMedals.compactMap { medal in
            guard let medalID = medal.id else { return nil }
            let response = MedalResponse(
                id: medalID,
                name: medal.name,
                description: medal.description,
                icon: medal.icon
            )
            let howToUnlock = howToUnlockByName[medal.name] ?? medal.description
            return MedalCatalogEntry(
                medal: response,
                earnedAt: earnedByMedalID[medalID],
                howToUnlock: howToUnlock
            )
        }

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
