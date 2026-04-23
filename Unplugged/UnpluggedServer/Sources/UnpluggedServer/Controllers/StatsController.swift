import Fluent
import UnpluggedShared
import Vapor

extension UserStatsResponse: @retroactive Content {}

struct StatsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("users")
        users.get("me", "stats", use: getMyStats)
    }

    @Sendable
    func getMyStats(req: Request) async throws -> UserStatsResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        return try await StatsService.getStats(for: userID, on: req.db)
    }
}
