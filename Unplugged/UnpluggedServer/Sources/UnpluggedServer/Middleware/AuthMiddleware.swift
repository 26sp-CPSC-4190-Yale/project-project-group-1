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
        request.auth.login(payload)

        // Touch last-seen timestamp for presence. Fire-and-forget — never block auth on this.
        if let userID = try? payload.userID {
            let db = request.db
            Task {
                if let user = try? await UserModel.find(userID, on: db) {
                    user.lastSeenAt = Date()
                    try? await user.save(on: db)
                }
            }
        }
    }
}
