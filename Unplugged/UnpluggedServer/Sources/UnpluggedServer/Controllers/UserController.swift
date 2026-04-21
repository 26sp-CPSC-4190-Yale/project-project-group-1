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
extension BlockedUser: @retroactive Content {}

struct UserController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("users")
        users.get("me", use: getMe)
        users.get("search", use: searchUsers)
        users.patch("me", use: updateMe)
        users.put("device-token", use: registerDeviceToken)
        users.delete("me", use: deleteMe)
        users.get("blocks", use: listBlocks)
        users.post(":userID", "block", use: blockUser)
        users.delete(":userID", "block", use: unblockUser)
        users.post(":userID", "report", use: reportUser)
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
    func searchUsers(req: Request) async throws -> [User] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        guard let query = req.query[String.self, at: "q"], !query.isEmpty else {
            return []
        }

        let hiddenIDs = try await BlockService.hiddenUserIDs(for: userID, on: req.db)

        let users = try await UserModel.query(on: req.db)
            .filter(\.$username, .custom("ILIKE"), "%\(query)%")
            .filter(\.$id != userID)
            .limit(20)
            .all()

        return users.compactMap {
            guard let id = try? $0.requireID(), !hiddenIDs.contains(id) else { return nil }
            return User(id: id, username: $0.username, createdAt: $0.createdAt ?? Date())
        }
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

    /// Soft-delete the authenticated account.
    ///
    /// App Store Guideline 5.1.1(v) requires in-app account deletion. We mark the user as
    /// deleted rather than hard-deleting immediately so (a) other participants' session
    /// history isn't corrupted mid-read, (b) accidental deletions can be restored during a
    /// grace window, (c) a background job can cascade cleanup asynchronously.
    ///
    /// For password-based accounts the client must re-authenticate by submitting the
    /// password in the request body; for OAuth accounts the JWT itself is the re-auth
    /// (the user just signed in with their provider to reach this screen, and the token
    /// was issued minutes ago).
    @Sendable
    func deleteMe(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        guard let user = try await UserModel.find(userID, on: req.db) else {
            throw Abort(.notFound)
        }

        if user.isDeleted {
            // Idempotent — already deleted, treat as success.
            return .noContent
        }

        // If this is a password account, require the password. OAuth-only accounts
        // (no usable password hash) skip this check because the JWT *is* the proof of identity.
        if user.appleSubject == nil && user.googleSubject == nil {
            let body = try? req.content.decode(DeleteAccountRequest.self)
            guard let password = body?.password else {
                throw Abort(.badRequest, reason: "Password required to delete account.")
            }
            guard try await req.password.async.verify(password, created: user.passwordHash) else {
                throw Abort(.unauthorized, reason: "Incorrect password.")
            }
        }

        user.deletedAt = Date()
        // Clear device token immediately so no further pushes are delivered.
        user.deviceToken = nil
        try await user.save(on: req.db)

        req.logger.info("user deleted", metadata: ["user_id": "\(userID)"])
        return .noContent
    }

    // MARK: - Block / Report

    /// Block another user. Idempotent. Also tears down any existing friendship so
    /// neither side sees the other in friend lists or notifications afterward.
    @Sendable
    func blockUser(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let blockerID = try payload.userID

        guard let idString = req.parameters.get("userID"),
              let blockedID = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }
        guard blockedID != blockerID else {
            throw Abort(.badRequest, reason: "Cannot block yourself.")
        }

        let existing = try await UserBlockModel.query(on: req.db)
            .filter(\.$blockerID == blockerID)
            .filter(\.$blockedID == blockedID)
            .first()
        if existing != nil { return .noContent }

        let block = UserBlockModel(blockerID: blockerID, blockedID: blockedID)
        try await block.save(on: req.db)

        // Remove any friendship in either direction so blocked users don't keep seeing each
        // other as friends / receive nudges.
        try await FriendshipModel.query(on: req.db)
            .group(.or) { group in
                group.group(.and) { g in
                    g.filter(\.$user1ID == blockerID)
                    g.filter(\.$user2ID == blockedID)
                }
                group.group(.and) { g in
                    g.filter(\.$user1ID == blockedID)
                    g.filter(\.$user2ID == blockerID)
                }
            }
            .delete()

        return .noContent
    }

    @Sendable
    func unblockUser(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let blockerID = try payload.userID

        guard let idString = req.parameters.get("userID"),
              let blockedID = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }

        try await UserBlockModel.query(on: req.db)
            .filter(\.$blockerID == blockerID)
            .filter(\.$blockedID == blockedID)
            .delete()
        return .noContent
    }

    @Sendable
    func listBlocks(req: Request) async throws -> [BlockedUser] {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        let blocks = try await UserBlockModel.query(on: req.db)
            .filter(\.$blockerID == userID)
            .all()
        let blockedIDs = blocks.map { $0.blockedID }
        guard !blockedIDs.isEmpty else { return [] }

        let users = try await UserModel.query(on: req.db)
            .filter(\.$id ~~ blockedIDs)
            .all()
        let userMap = Dictionary(uniqueKeysWithValues: users.compactMap { u -> (UUID, UserModel)? in
            guard let id = u.id else { return nil }
            return (id, u)
        })

        return blocks.compactMap { block in
            guard let user = userMap[block.blockedID] else { return nil }
            return BlockedUser(
                id: block.blockedID,
                username: user.username,
                blockedAt: block.createdAt ?? Date()
            )
        }
    }

    /// Submit a report against another user. App Store Guideline 1.2 requires a reporting
    /// mechanism for user-generated content; we persist the report for moderator review
    /// rather than taking automated action.
    @Sendable
    func reportUser(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let reporterID = try payload.userID

        guard let idString = req.parameters.get("userID"),
              let reportedID = UUID(uuidString: idString) else {
            throw Abort(.badRequest)
        }
        guard reportedID != reporterID else {
            throw Abort(.badRequest, reason: "Cannot report yourself.")
        }

        let body = try req.content.decode(ReportUserRequest.self)
        let trimmedReason = body.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty, trimmedReason.count <= 64 else {
            throw Abort(.badRequest, reason: "Report reason required.")
        }
        let trimmedDetails = body.details?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = trimmedDetails, d.count > 1000 {
            throw Abort(.badRequest, reason: "Details too long.")
        }

        let report = UserReportModel(
            reporterID: reporterID,
            reportedID: reportedID,
            reason: trimmedReason,
            details: (trimmedDetails?.isEmpty == true) ? nil : trimmedDetails
        )
        try await report.save(on: req.db)
        req.logger.warning("user report filed", metadata: [
            "reporter": "\(reporterID)",
            "reported": "\(reportedID)",
            "reason": "\(trimmedReason)"
        ])
        return .noContent
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
