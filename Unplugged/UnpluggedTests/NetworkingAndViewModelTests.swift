import Foundation
import XCTest
@testable import Unplugged
import UnpluggedShared

final class NetworkingAndViewModelTests: XCTestCase {
    func testAPIRouterSessionHistoryBuildsStableQueryItems() throws {
        let before = Date(timeIntervalSince1970: 1_777_777_777)
        let path = APIRouter.sessionHistory(limit: 15, before: before).path
        let components = try XCTUnwrap(URLComponents(string: "https://example.test\(path)"))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.path, "/sessions/history")
        XCTAssertEqual(items["limit"], "15")
        XCTAssertEqual(items["before"], "2026-05-03T03:09:37.000Z")
    }

    func testAPIClientAddsAuthorizationAndJSONBody() async throws {
        let seenRequest = RequestCapture()
        let user = User(id: UUID(), username: "alice", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try Self.encodeJSON(user)
        let session = StubSession { request in
            seenRequest.request = request
            return (data, Self.httpResponse(url: request.url!, status: 200))
        }
        let client = APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: session
        )

        let returned: User = try await client.send(.updateMe(UpdateUserRequest(username: "alice")))
        let request = try XCTUnwrap(seenRequest.request)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: String])

        XCTAssertEqual(returned.username, user.username)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/users/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(json["username"], "alice")
    }

    func testAPIClientDecodesFractionalAndStandardISO8601Dates() async throws {
        let payload = """
        [
          {
            "id": "\(UUID())",
            "title": "Fractional",
            "startedAt": "2026-04-28T10:15:30.500Z",
            "endedAt": "2026-04-28T11:15:30.500Z",
            "durationSeconds": 3600,
            "participantCount": 2,
            "leftEarly": false
          },
          {
            "id": "\(UUID())",
            "title": "Standard",
            "startedAt": "2026-04-28T12:00:00Z",
            "endedAt": "2026-04-28T13:00:00Z",
            "durationSeconds": 3600,
            "participantCount": 3,
            "leftEarly": true
          }
        ]
        """
        let session = StubSession { request in
            (Data(payload.utf8), Self.httpResponse(url: request.url!, status: 200))
        }
        let client = APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: session
        )

        let history: [SessionHistoryResponse] = try await client.send(.sessionHistory())

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(try XCTUnwrap(history[0].startedAt).timeIntervalSince1970, 1_777_371_330.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(history[1].endedAt).timeIntervalSince1970, 1_777_381_200, accuracy: 0.001)
    }

    func testAPIClientMapsHTTP400ReasonIntoNSError() async {
        let session = StubSession { request in
            let data = Data(#"{"error":true,"reason":"Invalid APNs device token."}"#.utf8)
            return (data, Self.httpResponse(url: request.url!, status: 400))
        }
        let client = APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: session
        )

        do {
            try await client.sendVoid(.registerDeviceToken("bad-token"))
            XCTFail("Expected request to fail")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "Vapor")
            XCTAssertEqual(nsError.code, 400)
            XCTAssertEqual(nsError.localizedDescription, "Invalid APNs device token.")
        }
    }

    @MainActor
    func testFriendsListLoadDeduplicatesFriendsAndNormalizesAcceptedStatus() async throws {
        let taylorID = UUID()
        let jordanID = UUID()
        let session = StubSession { request in
            switch request.url?.path {
            case "/friends":
                return (try Self.encodeJSON([
                    FriendResponse(id: taylorID, username: "Taylor"),
                    FriendResponse(id: UUID(), username: "taylor"),
                    FriendResponse(id: jordanID, username: "Jordan")
                ]), Self.httpResponse(url: request.url!, status: 200))
            case "/friends/requests/incoming":
                return (try Self.encodeJSON([FriendResponse(id: UUID(), username: "Incoming", status: "pending")]), Self.httpResponse(url: request.url!, status: 200))
            case "/friends/requests/outgoing":
                return (try Self.encodeJSON([FriendResponse(id: UUID(), username: "Outgoing", status: "pending")]), Self.httpResponse(url: request.url!, status: 200))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "<nil>")")
                throw URLError(.badURL)
            }
        }
        let service = FriendAPIService(client: APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: session
        ))
        let viewModel = FriendsListViewModel()

        let loaded = await viewModel.load(service: service, force: true)

        XCTAssertTrue(loaded)
        XCTAssertEqual(viewModel.friends.count, 2)
        XCTAssertTrue(viewModel.friends.allSatisfy { $0.status == "accepted" })
        XCTAssertEqual(viewModel.incomingRequests.count, 1)
        XCTAssertEqual(viewModel.outgoingRequests.count, 1)
    }

    @MainActor
    func testFriendsListAcceptRequestMovesUserIntoFriendsAndClearsIncoming() async throws {
        let request = FriendResponse(id: UUID(), username: "Casey", status: "pending")

        let initialService = FriendAPIService(client: APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: StubSession { requestURL in
                switch requestURL.url?.path {
                case "/friends":
                    return (try Self.encodeJSON([FriendResponse]()), Self.httpResponse(url: requestURL.url!, status: 200))
                case "/friends/requests/incoming":
                    return (try Self.encodeJSON([request]), Self.httpResponse(url: requestURL.url!, status: 200))
                case "/friends/requests/outgoing":
                    return (try Self.encodeJSON([FriendResponse]()), Self.httpResponse(url: requestURL.url!, status: 200))
                default:
                    XCTFail("Unexpected path \(requestURL.url?.path ?? "<nil>")")
                    throw URLError(.badURL)
                }
            }
        ))
        let acceptedFriend = FriendResponse(id: request.id, username: request.username, status: "accepted")
        let acceptService = FriendAPIService(client: APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: StubSession { requestURL in
                switch (requestURL.httpMethod, requestURL.url?.path) {
                case ("POST", "/friends/\(request.id)/accept"):
                    return (try Self.encodeJSON(acceptedFriend), Self.httpResponse(url: requestURL.url!, status: 200))
                case ("GET", "/friends"):
                    return (try Self.encodeJSON([acceptedFriend]), Self.httpResponse(url: requestURL.url!, status: 200))
                case ("GET", "/friends/requests/incoming"), ("GET", "/friends/requests/outgoing"):
                    return (try Self.encodeJSON([FriendResponse]()), Self.httpResponse(url: requestURL.url!, status: 200))
                default:
                    XCTFail("Unexpected request \(requestURL.httpMethod ?? "<nil>") \(requestURL.url?.path ?? "<nil>")")
                    throw URLError(.badURL)
                }
            }
        ))

        let viewModel = FriendsListViewModel()
        _ = await viewModel.load(service: initialService, force: true)

        await viewModel.acceptRequest(service: acceptService, requestID: request.id)

        XCTAssertEqual(viewModel.incomingRequests, [])
        XCTAssertEqual(viewModel.friends.map(\.username), ["Casey"])
        XCTAssertEqual(viewModel.friends.first?.status, "accepted")
        XCTAssertFalse(viewModel.isAccepting(requestID: request.id))
    }

    @MainActor
    func testFriendsListCancelOutgoingRequestClearsPendingRow() async throws {
        let request = FriendResponse(id: UUID(), username: "Morgan", status: "pending")

        let initialService = FriendAPIService(client: APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: StubSession { requestURL in
                switch requestURL.url?.path {
                case "/friends":
                    return (try Self.encodeJSON([FriendResponse]()), Self.httpResponse(url: requestURL.url!, status: 200))
                case "/friends/requests/incoming":
                    return (try Self.encodeJSON([FriendResponse]()), Self.httpResponse(url: requestURL.url!, status: 200))
                case "/friends/requests/outgoing":
                    return (try Self.encodeJSON([request]), Self.httpResponse(url: requestURL.url!, status: 200))
                default:
                    XCTFail("Unexpected path \(requestURL.url?.path ?? "<nil>")")
                    throw URLError(.badURL)
                }
            }
        ))
        let cancelService = FriendAPIService(client: APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: StubSession { requestURL in
                switch (requestURL.httpMethod, requestURL.url?.path) {
                case ("POST", "/friends/\(request.id)/reject"):
                    return (Data(), Self.httpResponse(url: requestURL.url!, status: 204))
                case ("GET", "/friends"), ("GET", "/friends/requests/incoming"), ("GET", "/friends/requests/outgoing"):
                    return (try Self.encodeJSON([FriendResponse]()), Self.httpResponse(url: requestURL.url!, status: 200))
                default:
                    XCTFail("Unexpected request \(requestURL.httpMethod ?? "<nil>") \(requestURL.url?.path ?? "<nil>")")
                    throw URLError(.badURL)
                }
            }
        ))

        let viewModel = FriendsListViewModel()
        _ = await viewModel.load(service: initialService, force: true)

        await viewModel.cancelOutgoingRequest(service: cancelService, targetID: request.id)

        XCTAssertEqual(viewModel.outgoingRequests, [])
        XCTAssertFalse(viewModel.isCancelling(requestID: request.id))
    }

    @MainActor
    func testFriendsListRemoveFriendPostsChangeNotification() async throws {
        let friend = FriendResponse(id: UUID(), username: "Riley", status: "accepted")
        let initialService = FriendAPIService(client: APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: StubSession { requestURL in
                switch requestURL.url?.path {
                case "/friends":
                    return (try Self.encodeJSON([friend]), Self.httpResponse(url: requestURL.url!, status: 200))
                case "/friends/requests/incoming", "/friends/requests/outgoing":
                    return (try Self.encodeJSON([FriendResponse]()), Self.httpResponse(url: requestURL.url!, status: 200))
                default:
                    XCTFail("Unexpected path \(requestURL.url?.path ?? "<nil>")")
                    throw URLError(.badURL)
                }
            }
        ))
        let removeService = FriendAPIService(client: APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: StubSession { requestURL in
                switch (requestURL.httpMethod, requestURL.url?.path) {
                case ("DELETE", "/friends/\(friend.id)"):
                    return (Data(), Self.httpResponse(url: requestURL.url!, status: 204))
                case ("GET", "/friends"), ("GET", "/friends/requests/incoming"), ("GET", "/friends/requests/outgoing"):
                    return (try Self.encodeJSON([FriendResponse]()), Self.httpResponse(url: requestURL.url!, status: 200))
                default:
                    XCTFail("Unexpected request \(requestURL.httpMethod ?? "<nil>") \(requestURL.url?.path ?? "<nil>")")
                    throw URLError(.badURL)
                }
            }
        ))

        let viewModel = FriendsListViewModel()
        _ = await viewModel.load(service: initialService, force: true)

        let notification = expectation(description: "Friends change notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .unpluggedFriendsDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notification.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await viewModel.removeFriend(service: removeService, friend: friend)
        await fulfillment(of: [notification], timeout: 1.0)

        XCTAssertEqual(viewModel.friends, [])
        XCTAssertFalse(viewModel.isRemovingFriend(friendID: friend.id))
    }

    @MainActor
    func testCreateRoomViewModelCreatesSessionAndSurfacesErrors() async throws {
        let sessionResponse = makeSessionResponse(title: "Deep Work", durationSeconds: 3_600)
        let successService = SessionAPIService(client: APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: StubSession { request in
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/sessions")
                return (try Self.encodeJSON(sessionResponse), Self.httpResponse(url: request.url!, status: 200))
            }
        ))
        let failureService = SessionAPIService(client: APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: StubSession { request in
                let data = Data(#"{"error":true,"reason":"Duration must be between 1 second and 24 hours."}"#.utf8)
                return (data, Self.httpResponse(url: request.url!, status: 400))
            }
        ))

        let viewModel = CreateRoomViewModel()
        viewModel.roomName = "   Deep Work   "

        XCTAssertTrue(viewModel.canCreate)
        XCTAssertEqual(viewModel.trimmedRoomName, "Deep Work")

        await viewModel.createRoom(title: "Deep Work", sessions: successService)
        XCTAssertEqual(viewModel.createdSession?.id, sessionResponse.id)
        XCTAssertNil(viewModel.error)

        await viewModel.createRoom(title: "Deep Work", sessions: failureService)
        XCTAssertNil(viewModel.createdSession)
        XCTAssertEqual(viewModel.error, "Failed to create room: Duration must be between 1 second and 24 hours.")
    }

    @MainActor
    func testGroupsViewModelCreateAddMemberAndDeleteUpdateState() async throws {
        let groupID = UUID()
        let ownerID = UUID()
        let memberID = UUID()
        let createdGroup = GroupResponse(
            id: groupID,
            name: "Besties",
            ownerID: ownerID,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            members: [
                GroupMemberResponse(id: UUID(), userID: ownerID, username: "owner", joinedAt: Date(timeIntervalSince1970: 1_700_000_000))
            ]
        )
        let updatedGroup = GroupResponse(
            id: groupID,
            name: "Besties",
            ownerID: ownerID,
            createdAt: createdGroup.createdAt,
            members: createdGroup.members + [
                GroupMemberResponse(id: UUID(), userID: memberID, username: "member", joinedAt: Date(timeIntervalSince1970: 1_700_000_100))
            ]
        )
        let createService = GroupAPIService(client: APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: StubSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("POST", "/groups"):
                    return (try Self.encodeJSON(createdGroup), Self.httpResponse(url: request.url!, status: 200))
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "<nil>") \(request.url?.path ?? "<nil>")")
                    throw URLError(.badURL)
                }
            }
        ))
        let updateService = GroupAPIService(client: APIClient(
            baseURL: "https://example.test",
            cachedToken: { "jwt-token" },
            session: StubSession { request in
                switch (request.httpMethod, request.url?.path) {
                case ("POST", "/groups/\(groupID)/members"):
                    return (try Self.encodeJSON(updatedGroup), Self.httpResponse(url: request.url!, status: 200))
                case ("DELETE", "/groups/\(groupID)"):
                    return (Data(), Self.httpResponse(url: request.url!, status: 204))
                default:
                    XCTFail("Unexpected request \(request.httpMethod ?? "<nil>") \(request.url?.path ?? "<nil>")")
                    throw URLError(.badURL)
                }
            }
        ))

        let viewModel = GroupsViewModel()
        viewModel.newGroupName = "  Besties  "

        await viewModel.createGroup(service: createService)
        XCTAssertEqual(viewModel.groups.map(\.name), ["Besties"])
        XCTAssertFalse(viewModel.showCreate)

        await viewModel.addMember(to: createdGroup, userID: memberID, service: updateService)
        XCTAssertEqual(viewModel.groups.first?.members.count, 2)

        await viewModel.deleteGroup(updatedGroup, service: updateService)
        XCTAssertTrue(viewModel.groups.isEmpty)
    }
}

private extension NetworkingAndViewModelTests {
    final class RequestCapture {
        var request: URLRequest?
    }

    struct StubSession: HTTPSession {
        let handler: (URLRequest) async throws -> (Data, URLResponse)

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            try await handler(request)
        }
    }

    static func httpResponse(
        url: URL,
        status: Int,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    func makeSessionResponse(title: String, durationSeconds: Int) -> SessionResponse {
        let sessionID = UUID()
        let hostID = UUID()
        let participantID = UUID()
        return SessionResponse(
            session: Session(
                id: sessionID,
                code: "ABC123",
                hostID: hostID,
                state: .idle,
                title: title,
                durationSeconds: durationSeconds,
                startedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            participants: [
                ParticipantResponse(
                    id: participantID,
                    userID: hostID,
                    username: "host",
                    status: .active,
                    joinedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    isHost: true
                )
            ]
        )
    }
}
