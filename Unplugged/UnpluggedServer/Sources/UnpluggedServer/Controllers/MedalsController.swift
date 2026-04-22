import Fluent
import UnpluggedShared
import Vapor

extension MedalResponse: @retroactive Content {}
extension UserMedalResponse: @retroactive Content {}

struct MedalsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let medals = routes.grouped("medals")
        medals.post(use: createMedal)
        medals.get(use: getAllMedals)

        let users = routes.grouped("users")
        users.get("me", "medals", use: getMyMedals)
        users.post(":userID", "medals", ":medalID", use: awardMedal)
        users.get(":userID", "medals", use: getUserMedals)
    }

    // Empty ADMIN_USER_IDS => nobody passes => all admin endpoints 403.
    private func requireAdmin(_ req: Request) throws {
        let payload = try req.auth.require(UserPayload.self)
        let callerID = try payload.userID
        let raw = Environment.get("ADMIN_USER_IDS") ?? ""
        let allowed = raw
            .split(separator: ",")
            .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        guard allowed.contains(callerID) else {
            throw Abort(.forbidden, reason: "Admin privileges required.")
        }
    }

    func createMedal(req: Request) async throws -> MedalResponse {
        try requireAdmin(req)
        let medal = try req.content.decode(MedalModel.self)
        try await medal.save(on: req.db)
        guard let id = medal.id else { throw Abort(.internalServerError) }
        return MedalResponse(id: id, name: medal.name, description: medal.description, icon: medal.icon)
    }

    func getAllMedals(req: Request) async throws -> [MedalResponse] {
        let medals = try await MedalModel.query(on: req.db).all()
        return medals.compactMap { medal in
            guard let id = medal.id else { return nil }
            return MedalResponse(id: id, name: medal.name, description: medal.description, icon: medal.icon)
        }
    }

    func awardMedal(req: Request) async throws -> HTTPStatus {
        try requireAdmin(req)
        guard let userID = req.parameters.get("userID", as: UUID.self),
              let medalID = req.parameters.get("medalID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let pivot = UserMedalPivot(userID: userID, medalID: medalID)
        try await pivot.save(on: req.db)
        return .created
    }

    func getUserMedals(req: Request) async throws -> [UserMedalResponse] {
        guard let userID = req.parameters.get("userID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await MedalService.getUserMedals(userID: userID, on: req.db)
    }

    func getMyMedals(req: Request) async throws -> [UserMedalResponse] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        return try await MedalService.getUserMedals(userID: userID, on: req.db)
    }
}