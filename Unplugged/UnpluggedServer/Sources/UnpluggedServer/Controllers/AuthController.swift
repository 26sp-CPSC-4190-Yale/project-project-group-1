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
        auth.post("apple", use: signInWithApple)
        auth.post("google", use: signInWithGoogle)
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

        let hash = try await req.password.async.hash(body.password)
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

        guard try await req.password.async.verify(body.password, created: user.passwordHash) else {
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

    // MARK: - OAuth

    @Sendable
    func signInWithApple(req: Request) async throws -> AuthResponse {
        let body = try req.content.decode(AppleSignInRequest.self)

        let appleToken: AppleIdentityToken
        do {
            appleToken = try await req.jwt.apple.verify(body.identityToken)
        } catch {
            req.logger.warning("Apple identity token verification failed: \(error)")
            throw Abort(.unauthorized, reason: "Invalid Apple identity token.")
        }

        let subject = appleToken.subject.value

        // Try to find an existing user linked to this Apple subject
        if let existing = try await UserModel.query(on: req.db)
            .filter(\.$appleSubject == subject)
            .first() {
            return try await issueToken(for: existing, req: req)
        }

        // Otherwise create a new user. Username must be unique, so derive one.
        let baseUsername = usernameCandidate(
            fromFullName: body.fullName,
            email: body.email ?? appleToken.email,
            fallback: "apple_\(String(subject.suffix(8)))"
        )
        let username = try await uniqueUsername(baseUsername, on: req.db)

        let user = UserModel()
        user.username = username
        // No password for OAuth accounts — store a random unusable hash.
        user.passwordHash = try await req.password.async.hash(UUID().uuidString)
        user.appleSubject = subject
        try await user.save(on: req.db)

        return try await issueToken(for: user, req: req)
    }

    @Sendable
    func signInWithGoogle(req: Request) async throws -> AuthResponse {
        let body = try req.content.decode(GoogleSignInRequest.self)

        let googleToken: GoogleIdentityToken
        do {
            googleToken = try await req.jwt.google.verify(body.idToken)
        } catch {
            req.logger.warning("Google identity token verification failed: \(error)")
            throw Abort(.unauthorized, reason: "Invalid Google ID token.")
        }

        let subject = googleToken.subject.value

        if let existing = try await UserModel.query(on: req.db)
            .filter(\.$googleSubject == subject)
            .first() {
            return try await issueToken(for: existing, req: req)
        }

        let baseUsername = usernameCandidate(
            fromFullName: googleToken.name,
            email: googleToken.email,
            fallback: "google_\(String(subject.suffix(8)))"
        )
        let username = try await uniqueUsername(baseUsername, on: req.db)

        let user = UserModel()
        user.username = username
        user.passwordHash = try await req.password.async.hash(UUID().uuidString)
        user.googleSubject = subject
        try await user.save(on: req.db)

        return try await issueToken(for: user, req: req)
    }

    // MARK: - OAuth helpers

    private func issueToken(for user: UserModel, req: Request) async throws -> AuthResponse {
        let userID = try user.requireID()
        let payload = UserPayload.create(userID: userID)
        let token = try await req.jwt.sign(payload)
        return AuthResponse(
            token: token,
            user: User(id: userID, username: user.username, createdAt: user.createdAt ?? Date())
        )
    }

    /// Derive a safe base username from full name → email local part → fallback.
    private func usernameCandidate(fromFullName fullName: String?, email: String?, fallback: String) -> String {
        if let fullName,
           let sanitized = sanitizeUsername(fullName),
           !sanitized.isEmpty {
            return sanitized
        }
        if let email,
           let local = email.split(separator: "@").first,
           let sanitized = sanitizeUsername(String(local)),
           !sanitized.isEmpty {
            return sanitized
        }
        return sanitizeUsername(fallback) ?? "user\(Int.random(in: 1000...9999))"
    }

    /// Filter a string down to letters/numbers and clamp to the InputValidation rules (3–20 chars).
    private func sanitizeUsername(_ raw: String) -> String? {
        let filtered = raw.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init)
        let cleaned = String(filtered)
        guard !cleaned.isEmpty else { return nil }
        let clamped = String(cleaned.prefix(20))
        if clamped.count < 3 {
            return clamped + String(repeating: "0", count: 3 - clamped.count)
        }
        return clamped
    }

    /// Ensure uniqueness by appending a numeric suffix as needed.
    private func uniqueUsername(_ base: String, on db: Database) async throws -> String {
        var candidate = base
        var counter = 1
        while try await UserModel.query(on: db).filter(\.$username == candidate).first() != nil {
            let suffix = String(counter)
            let trimmed = String(base.prefix(max(0, 20 - suffix.count)))
            candidate = trimmed + suffix
            counter += 1
            if counter > 1000 {
                throw Abort(.internalServerError, reason: "Could not derive unique username.")
            }
        }
        return candidate
    }
}
