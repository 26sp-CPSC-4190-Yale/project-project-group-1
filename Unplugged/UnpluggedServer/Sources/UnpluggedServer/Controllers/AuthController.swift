//
//  AuthController.swift
//  UnpluggedServer.Controllers
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
import JWT
import UnpluggedShared
import Vapor

extension AuthResponse: @retroactive Content {}

struct AuthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("register", use: register)
        auth.post("login", use: login)
    }

    @Sendable
    func register(req: Request) async throws -> AuthResponse {
        let body = try req.content.decode(RegisterRequest.self)

        guard InputValidation.isValidUsername(body.username) else {
            throw Abort(.badRequest, reason: "Username must be 3-20 characters, letters/numbers only.")
        }
        guard InputValidation.isValidPassword(body.password) else {
            throw Abort(.badRequest, reason: "Password must be at least 8 characters.")
        }

        let existing = try await UserModel.query(on: req.db)
            .filter(\.$username == body.username)
            .first()
        guard existing == nil else {
            throw Abort(.conflict, reason: "Username already taken.")
        }

        let hash = try Bcrypt.hash(body.password)
        let user = UserModel()
        user.username = body.username
        user.passwordHash = hash
        try await user.save(on: req.db)

        let userID = try user.requireID()
        let payload = UserPayload.create(userID: userID)
        let token = try await req.jwt.sign(payload)
        return AuthResponse(
            token: token,
            user: User(id: userID, username: user.username, createdAt: user.createdAt ?? Date())
        )
    }

    @Sendable
    func login(req: Request) async throws -> AuthResponse {
        let body = try req.content.decode(LoginRequest.self)

        guard let user = try await UserModel.query(on: req.db)
            .filter(\.$username == body.username)
            .first()
        else {
            throw Abort(.unauthorized, reason: "Invalid credentials.")
        }

        guard try Bcrypt.verify(body.password, created: user.passwordHash) else {
            throw Abort(.unauthorized, reason: "Invalid credentials.")
        }

        let userID = try user.requireID()
        let payload = UserPayload.create(userID: userID)
        let token = try await req.jwt.sign(payload)
        return AuthResponse(
            token: token,
            user: User(id: userID, username: user.username, createdAt: user.createdAt ?? Date())
        )
    }
}
