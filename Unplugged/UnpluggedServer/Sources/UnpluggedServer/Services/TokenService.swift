//
//  TokenService.swift
//  UnpluggedServer.Services
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import JWT
import Vapor

struct UserPayload: JWTPayload, Authenticatable {
    var subject: SubjectClaim
    var expiration: ExpirationClaim

    func verify(using key: some JWTAlgorithm) async throws {
        try expiration.verifyNotExpired()
    }

    var userID: UUID {
        get throws {
            guard let id = UUID(uuidString: subject.value) else {
                throw Abort(.unauthorized)
            }
            return id
        }
    }

    static func create(userID: UUID) -> UserPayload {
        UserPayload(
            subject: SubjectClaim(value: userID.uuidString),
            expiration: ExpirationClaim(value: Date().addingTimeInterval(60 * 60 * 24 * 7))
        )
    }
}
