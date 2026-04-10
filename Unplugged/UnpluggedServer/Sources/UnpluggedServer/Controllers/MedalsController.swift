import Fluent
import Vapor

struct MedalsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let medals = routes.grouped("medals")
        medals.post(use: createMedal)         // POST /medals
        medals.get(use: getAllMedals)          // GET  /medals

        let users = routes.grouped("users")
        users.post(":userID", "medals", ":medalID", use: awardMedal)  // POST /users/:userID/medals/:medalID
        users.get(":userID", "medals", use: getUserMedals)            // GET  /users/:userID/medals
    }

    // Create a new medal type
    func createMedal(req: Request) async throws -> MedalModel {
        let medal = try req.content.decode(MedalModel.self)
        try await medal.save(on: req.db)
        return medal
    }

    // List all medal types
    func getAllMedals(req: Request) async throws -> [MedalModel] {
        try await MedalModel.query(on: req.db).all()
    }

    // Award a medal to a user
    func awardMedal(req: Request) async throws -> HTTPStatus {
        guard let userID = req.parameters.get("userID", as: UUID.self),
              let medalID = req.parameters.get("medalID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let pivot = UserMedalPivot(userID: userID, medalID: medalID)
        try await pivot.save(on: req.db)
        return .created
    }

    // Get all medals for a user
    func getUserMedals(req: Request) async throws -> [MedalModel] {
        guard let userID = req.parameters.get("userID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let user = try await UserModel.find(userID, on: req.db) ?? { throw Abort(.notFound) }()
        try await user.$medals.load(on: req.db)
        return user.medals
    }
}