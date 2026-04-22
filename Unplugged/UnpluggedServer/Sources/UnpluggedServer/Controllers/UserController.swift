//
//  UserController.swift
//  UnpluggedServer.Controllers
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
import UnpluggedShared
import Vapor

extension User: @retroactive Content {}
extension UserStatsResponse: @retroactive Content {}

struct UserController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("users")
        users.get("me", use: getMe)
        users.patch("me", use: updateMe)
        users.put("device-token", use: registerDeviceToken)
        users.get("me", "stats", use: getMyStats)
    }

    @Sendable
    func getMe(req: Request) async throws -> User {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        guard let user = try await UserModel.find(userID, on: req.db) else {
            throw Abort(.notFound)
        }
        return User(id: userID, username: user.username, createdAt: user.createdAt ?? Date())
    }

    @Sendable
    func updateMe(req: Request) async throws -> User {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let body = try req.content.decode(UpdateUserRequest.self)
        guard InputValidation.isValidUsername(body.username) else {
            throw Abort(.badRequest, reason: "Username must be 3–20 characters, letters/numbers only.")
        }

        guard let user = try await UserModel.find(userID, on: req.db) else {
            throw Abort(.notFound)
        }

        let existing = try await UserModel.query(on: req.db)
            .filter(\.$username == body.username)
            .first()
        if let existing, existing.id != userID {
            throw Abort(.conflict, reason: "Username already taken.")
        }

        user.username = body.username
        try await user.save(on: req.db)
        return User(id: userID, username: user.username, createdAt: user.createdAt ?? Date())
    }

    @Sendable
    func getMyStats(req: Request) async throws -> UserStatsResponse {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID
        return try await StatsService(db: req.db).getStats(for: userID)
    }

    @Sendable
    func registerDeviceToken(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let body = try req.content.decode(DeviceTokenRequest.self)

        guard let user = try await UserModel.find(userID, on: req.db) else {
            throw Abort(.notFound)
        }

        user.deviceToken = body.deviceToken
        try await user.save(on: req.db)
        return .noContent
    }
}
