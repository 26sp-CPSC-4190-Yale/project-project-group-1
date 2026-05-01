import Fluent
import UnpluggedShared
import Vapor

enum UserVisibilityService {
    static func visibleUser(_ id: UUID, on db: Database) async throws -> UserModel? {
        try await UserModel.query(on: db)
            .filter(\.$id == id)
            .filter(\.$deletedAt == nil)
            .first()
    }

    static func visibleUsers(_ ids: [UUID], on db: Database) async throws -> [UserModel] {
        guard !ids.isEmpty else { return [] }
        return try await UserModel.query(on: db)
            .filter(\.$id ~~ ids)
            .filter(\.$deletedAt == nil)
            .all()
    }

    static func findByUsername(_ username: String, on db: Database) async throws -> UserModel? {
        try await UserModel.query(on: db)
            .filter(\.$username, caseInsensitiveLikeOperator(for: db), InputValidation.normalizedUsername(username))
            .filter(\.$deletedAt == nil)
            .first()
    }

    static func usernameExists(_ username: String, excluding excludedID: UUID? = nil, on db: Database) async throws -> Bool {
        var query = UserModel.query(on: db)
            .filter(\.$username, caseInsensitiveLikeOperator(for: db), InputValidation.normalizedUsername(username))
            .filter(\.$deletedAt == nil)
        if let excludedID {
            query = query.filter(\.$id != excludedID)
        }
        return try await query.first() != nil
    }

    static func publicUser(_ user: UserModel) throws -> User {
        let id = try user.requireID()
        return User(id: id, username: user.username, createdAt: user.createdAt ?? Date())
    }
}

