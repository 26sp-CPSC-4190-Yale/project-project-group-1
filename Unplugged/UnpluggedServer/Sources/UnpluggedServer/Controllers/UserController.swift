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

    // soft-delete per App Store Guideline 5.1.1(v), password accounts re-auth via body, OAuth relies on the recent JWT
    @Sendable
    func deleteMe(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
        let userID = try payload.userID

        guard let user = try await UserModel.find(userID, on: req.db) else {
            throw Abort(.notFound)
        }

        if user.isDeleted {
            return .noContent
        }

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
        user.deviceToken = nil
        try await user.save(on: req.db)

        req.logger.info("user deleted", metadata: ["user_id": "\(userID)"])
        return .noContent
    }

    // MARK: - Block / Report

    // idempotent, also tears down any existing friendship in either direction
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

    // required by App Store Guideline 1.2, reports are persisted for manual moderator review only
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
        guard let normalizedToken = Self.normalizedAPNsToken(body.deviceToken) else {
            throw Abort(.badRequest, reason: "Invalid APNs device token.")
        }

        guard let user = try await UserModel.find(userID, on: req.db) else {
            throw Abort(.notFound)
        }

        user.deviceToken = normalizedToken
        try await user.save(on: req.db)
        return .noContent
    }
}

private extension UserController {
    static func normalizedAPNsToken(_ raw: String) -> String? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let isHex = normalized.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdef").contains($0)
        }

        guard normalized.count == 64, isHex else {
            return nil
        }
        return normalized
    }
}
