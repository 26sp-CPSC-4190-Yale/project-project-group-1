//
//  AuthMiddleware.swift
//  UnpluggedServer.Middleware
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import JWT
import Vapor

struct JWTAuthMiddleware: AsyncBearerAuthenticator {
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        let payload = try await request.jwt.verify(bearer.token, as: UserPayload.self)
        request.auth.login(payload)
    }
}
