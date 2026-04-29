import Fluent
import FluentSQLiteDriver
import JWT
import NIOCore
import Vapor
import XCTest
import XCTVapor
@testable import UnpluggedServer
import UnpluggedShared

struct TestUser {
    let id: UUID
    let username: String
    let token: String
}

enum TestAppFactory {
    private static let jwtSecret = "test-secret-that-is-at-least-32-characters"
    static let defaultPassword = "Password1!"

    static func make() async throws -> Application {
        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite)
        await app.jwt.keys.add(
            hmac: HMACKey(key: SymmetricKey(data: Data(jwtSecret.utf8))),
            digestAlgorithm: .sha256
        )

        app.migrations.add(TestCreateUsers())
        app.migrations.add(TestCreateRooms())
        app.migrations.add(TestCreateMembers())
        app.migrations.add(TestCreateFriendships())
        app.migrations.add(TestCreateGroups())
        app.migrations.add(TestCreateGroupMembers())
        app.migrations.add(TestCreateJailbreaks())
        app.migrations.add(TestCreateMedals())
        app.migrations.add(TestCreateUserMedalPivot())
        app.migrations.add(TestCreateUserBlocks())
        app.migrations.add(TestCreateUserReports())

        try await app.autoMigrate()
        try routes(app)
        return app
    }

    static func seedUser(
        on app: Application,
        username: String,
        lastSeenAt: Date? = nil,
        deletedAt: Date? = nil
    ) async throws -> TestUser {
        let user = UserModel(username: username, passwordHash: try Bcrypt.hash(defaultPassword))
        user.lastSeenAt = lastSeenAt
        user.deletedAt = deletedAt
        try await user.save(on: app.db)

        let id = try user.requireID()
        let token = try await app.jwt.keys.sign(UserPayload.create(userID: id))
        return TestUser(id: id, username: username, token: token)
    }

    static func seedAcceptedFriendship(on app: Application, between first: TestUser, and second: TestUser) async throws {
        let friendship = FriendshipModel(user1ID: first.id, user2ID: second.id, status: "accepted")
        try await friendship.save(on: app.db)
    }

    static func jsonBody<T: Encodable>(_ value: T) throws -> ByteBuffer {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        return buffer
    }

    static func decode<T: Decodable>(_ type: T.Type, from response: XCTHTTPResponse) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try XCTUnwrap(
            response.body.getData(at: response.body.readerIndex, length: response.body.readableBytes)
        )
        return try decoder.decode(T.self, from: data)
    }

    static func registerUser(
        with tester: any XCTApplicationTester,
        username: String,
        password: String = defaultPassword
    ) async throws -> AuthResponse {
        let response = try await sendRequest(
            with: tester,
            .POST,
            "/auth/register",
            body: RegisterRequest(username: username, password: password)
        )
        return try decode(AuthResponse.self, from: response)
    }

    static func loginUser(
        with tester: any XCTApplicationTester,
        username: String,
        password: String = defaultPassword
    ) async throws -> AuthResponse {
        let response = try await sendRequest(
            with: tester,
            .POST,
            "/auth/login",
            body: LoginRequest(username: username, password: password)
        )
        return try decode(AuthResponse.self, from: response)
    }

    static func sendRequest(
        with tester: any XCTApplicationTester,
        _ method: HTTPMethod,
        _ path: String,
        token: String? = nil
    ) async throws -> XCTHTTPResponse {
        try await tester.sendRequest(method, path, headers: headers(token: token))
    }

    static func sendRequest<T: Encodable>(
        with tester: any XCTApplicationTester,
        _ method: HTTPMethod,
        _ path: String,
        token: String? = nil,
        body: T
    ) async throws -> XCTHTTPResponse {
        try await tester.sendRequest(
            method,
            path,
            headers: headers(token: token, json: true),
            body: try jsonBody(body)
        )
    }

    static func headers(token: String? = nil, json: Bool = false) -> HTTPHeaders {
        var headers = HTTPHeaders()
        if let token {
            headers.add(name: .authorization, value: "Bearer \(token)")
        }
        if json {
            headers.add(name: .contentType, value: "application/json")
            headers.add(name: .accept, value: "application/json")
        }
        return headers
    }
}

struct TestCreateUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(UserModel.schema)
            .id()
            .field("username", .string, .required)
            .field("password_hash", .string, .required)
            .field("points", .int, .required)
            .field("device_token", .string)
            .field("last_seen_at", .datetime)
            .field("presence_expires_at", .datetime)
            .field("apple_subject", .string)
            .field("google_subject", .string)
            .field("created_at", .datetime)
            .field("deleted_at", .datetime)
            .unique(on: "username")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(UserModel.schema).delete()
    }
}

struct TestCreateRooms: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(RoomModel.schema)
            .id()
            .field("room_owner", .uuid, .required)
            .field("start_time", .datetime, .required)
            .field("latitude", .double)
            .field("longitude", .double)
            .field("code", .string)
            .field("title", .string)
            .field("duration_seconds", .int)
            .field("locked_at", .datetime)
            .field("ended_at", .datetime)
            .unique(on: "code")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(RoomModel.schema).delete()
    }
}

struct TestCreateMembers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(MemberModel.schema)
            .id()
            .field("user_id", .uuid, .required)
            .field("room_id", .uuid, .required)
            .field("config", .string)
            .field("joined_at", .datetime, .required)
            .field("left_at", .datetime)
            .field("left_early", .bool, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(MemberModel.schema).delete()
    }
}

struct TestCreateFriendships: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(FriendshipModel.schema)
            .id()
            .field("user_1_id", .uuid, .required)
            .field("user_2_id", .uuid, .required)
            .field("status", .string, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(FriendshipModel.schema).delete()
    }
}

struct TestCreateGroups: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(GroupModel.schema)
            .id()
            .field("name", .string, .required)
            .field("owner_id", .uuid, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(GroupModel.schema).delete()
    }
}

struct TestCreateGroupMembers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(GroupMemberModel.schema)
            .id()
            .field("group_id", .uuid, .required)
            .field("user_id", .uuid, .required)
            .field("joined_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(GroupMemberModel.schema).delete()
    }
}

struct TestCreateJailbreaks: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(JailbreakModel.schema)
            .id()
            .field("session_id", .uuid, .required)
            .field("user_id", .uuid, .required)
            .field("detected_at", .datetime, .required)
            .field("reason", .string)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(JailbreakModel.schema).delete()
    }
}

struct TestCreateMedals: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(MedalModel.schema)
            .id()
            .field("name", .string, .required)
            .field("description", .string, .required)
            .field("icon", .string, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(MedalModel.schema).delete()
    }
}

struct TestCreateUserMedalPivot: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(UserMedalPivot.schema)
            .id()
            .field("user_id", .uuid, .required)
            .field("medal_id", .uuid, .required)
            .field("earned_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(UserMedalPivot.schema).delete()
    }
}

struct TestCreateUserBlocks: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(UserBlockModel.schema)
            .id()
            .field("blocker_id", .uuid, .required)
            .field("blocked_id", .uuid, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(UserBlockModel.schema).delete()
    }
}

struct TestCreateUserReports: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(UserReportModel.schema)
            .id()
            .field("reporter_id", .uuid, .required)
            .field("reported_id", .uuid, .required)
            .field("reason", .string, .required)
            .field("details", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(UserReportModel.schema).delete()
    }
}
