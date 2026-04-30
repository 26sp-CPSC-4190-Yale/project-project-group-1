import Fluent
import JWT
import Vapor

struct JWTAuthMiddleware: AsyncBearerAuthenticator {
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        let payload = try await request.jwt.verify(bearer.token, as: UserPayload.self)

        // checked here rather than per-controller, otherwise a deleted user could sneak a mutating request through during the grace window
        if let userID = try? payload.userID,
           let user = try await UserModel.find(userID, on: request.db),
           user.isDeleted {
            throw Abort(.unauthorized, reason: "Account deleted")
        }

        request.auth.login(payload)
    }
}
