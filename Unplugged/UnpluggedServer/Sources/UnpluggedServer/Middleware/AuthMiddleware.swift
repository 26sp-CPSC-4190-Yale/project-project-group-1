//
//  AuthMiddleware.swift
//  UnpluggedServer.Middleware
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
import JWT
import Vapor

struct JWTAuthMiddleware: AsyncBearerAuthenticator {
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        let payload = try await request.jwt.verify(bearer.token, as: UserPayload.self)

        // Reject tokens for accounts that have initiated deletion. Doing this inside the
        // middleware (rather than at every controller) guarantees a deleted user can't
        // sneak a mutating request through during the grace window.
        if let userID = try? payload.userID,
           let user = try await UserModel.find(userID, on: request.db),
           user.isDeleted {
            throw Abort(.unauthorized, reason: "Account deleted")
        }

        request.auth.login(payload)

        // Touch last-seen timestamp for presence. Fire-and-forget — never block auth on this.
        if let userID = try? payload.userID {
            let db = request.db
            let logger = request.logger
            Task {
                do {
                    guard let user = try await UserModel.find(userID, on: db), !user.isDeleted else { return }
                    user.lastSeenAt = Date()
                    try await user.save(on: db)
                } catch {
                    logger.warning("lastSeenAt update failed for user \(userID): \(error)")
                }
            }
        }
    }
}
