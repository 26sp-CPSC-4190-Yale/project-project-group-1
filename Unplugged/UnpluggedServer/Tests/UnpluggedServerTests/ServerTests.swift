import Fluent
import Foundation
import XCTest
import XCTVapor
@testable import UnpluggedServer
import UnpluggedShared

final class ServerTests: XCTestCase {
    func testRegisterLoginAndGetMeRoundTrip() async throws {
        try await withApp { _, tester in
            let registered = try await TestAppFactory.registerUser(with: tester, username: "RouteUser")
            let loggedIn = try await TestAppFactory.loginUser(with: tester, username: "RouteUser")
            let meResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/users/me",
                token: registered.token
            )
            let me = try TestAppFactory.decode(User.self, from: meResponse)

            XCTAssertEqual(meResponse.status, .ok)
            XCTAssertEqual(registered.user.username, "RouteUser")
            XCTAssertEqual(loggedIn.user.id, registered.user.id)
            XCTAssertEqual(me.id, registered.user.id)
            XCTAssertEqual(me.username, "RouteUser")
        }
    }

    func testUsernameUniquenessIsCaseInsensitive() async throws {
        try await withApp { app, tester in
            _ = try await TestAppFactory.seedUser(on: app, username: "CaseUser")
            let duplicateResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/auth/register",
                body: RegisterRequest(username: "caseuser", password: TestAppFactory.defaultPassword)
            )

            XCTAssertEqual(duplicateResponse.status, .conflict)
        }
    }

    func testUpdateSearchAndDeviceTokenNormalization() async throws {
        try await withApp { app, tester in
            let alpha = try await TestAppFactory.seedUser(on: app, username: "AlphaUser")
            let searcher = try await TestAppFactory.seedUser(on: app, username: "Searcher")
            let staleTokenOwnerRecord = try await UserModel.find(searcher.id, on: app.db)
            let staleTokenOwner = try XCTUnwrap(staleTokenOwnerRecord)
            staleTokenOwner.deviceToken = "aabbccddeeff00112233445566778899"
            try await staleTokenOwner.save(on: app.db)

            let updateResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .PATCH,
                "/users/me",
                token: alpha.token,
                body: UpdateUserRequest(username: "RenamedAlpha")
            )
            let invalidTokenResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .PUT,
                "/users/device-token",
                token: alpha.token,
                body: DeviceTokenRequest(deviceToken: "xyz")
            )
            let validTokenResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .PUT,
                "/users/device-token",
                token: alpha.token,
                body: DeviceTokenRequest(deviceToken: "<AABBCCDDEEFF00112233445566778899>")
            )
            let clearTokenResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .DELETE,
                "/users/device-token",
                token: alpha.token
            )
            let searchResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/users/search?q=renamedalpha",
                token: searcher.token
            )

            let updated = try TestAppFactory.decode(User.self, from: updateResponse)
            let found = try TestAppFactory.decode([User].self, from: searchResponse)
            let storedUserRecord = try await UserModel.find(alpha.id, on: app.db)
            let storedUser = try XCTUnwrap(storedUserRecord)
            let staleTokenOwnerAfterRecord = try await UserModel.find(searcher.id, on: app.db)
            let staleTokenOwnerAfter = try XCTUnwrap(staleTokenOwnerAfterRecord)

            XCTAssertEqual(updateResponse.status, .ok)
            XCTAssertEqual(updated.username, "RenamedAlpha")
            XCTAssertEqual(invalidTokenResponse.status, .badRequest)
            XCTAssertEqual(validTokenResponse.status, .noContent)
            XCTAssertEqual(clearTokenResponse.status, .noContent)
            XCTAssertEqual(found.map(\.id), [alpha.id])
            XCTAssertNil(storedUser.deviceToken)
            XCTAssertNil(staleTokenOwnerAfter.deviceToken)
        }
    }

    func testFriendRequestAcceptFlowUpdatesIncomingOutgoingAndFriends() async throws {
        try await withApp { app, tester in
            let alice = try await TestAppFactory.seedUser(on: app, username: "FriendAlpha")
            let bob = try await TestAppFactory.seedUser(on: app, username: "FriendBeta")

            let addResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/friends",
                token: alice.token,
                body: AddFriendRequest(username: bob.username.lowercased())
            )
            let aliceOutgoingResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/friends/requests/outgoing",
                token: alice.token
            )
            let bobIncomingResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/friends/requests/incoming",
                token: bob.token
            )
            let acceptResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/friends/\(alice.id)/accept",
                token: bob.token
            )
            let aliceFriendsResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/friends",
                token: alice.token
            )
            let bobFriendsResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/friends",
                token: bob.token
            )

            let added = try TestAppFactory.decode(FriendResponse.self, from: addResponse)
            let aliceOutgoing = try TestAppFactory.decode([FriendResponse].self, from: aliceOutgoingResponse)
            let bobIncoming = try TestAppFactory.decode([FriendResponse].self, from: bobIncomingResponse)
            let accepted = try TestAppFactory.decode(FriendResponse.self, from: acceptResponse)
            let aliceFriends = try TestAppFactory.decode([FriendResponse].self, from: aliceFriendsResponse)
            let bobFriends = try TestAppFactory.decode([FriendResponse].self, from: bobFriendsResponse)

            XCTAssertEqual(added.username, bob.username)
            XCTAssertEqual(aliceOutgoing.map(\.id), [bob.id])
            XCTAssertEqual(bobIncoming.map(\.id), [alice.id])
            XCTAssertEqual(accepted.id, alice.id)
            XCTAssertEqual(aliceFriends.map(\.id), [bob.id])
            XCTAssertEqual(bobFriends.map(\.id), [alice.id])

            let aliceOutgoingAfter = try TestAppFactory.decode(
                [FriendResponse].self,
                from: try await TestAppFactory.sendRequest(
                    with: tester,
                    .GET,
                    "/friends/requests/outgoing",
                    token: alice.token
                )
            )
            let bobIncomingAfter = try TestAppFactory.decode(
                [FriendResponse].self,
                from: try await TestAppFactory.sendRequest(
                    with: tester,
                    .GET,
                    "/friends/requests/incoming",
                    token: bob.token
                )
            )

            XCTAssertTrue(aliceOutgoingAfter.isEmpty)
            XCTAssertTrue(bobIncomingAfter.isEmpty)
        }
    }

    func testReciprocalFriendRequestAutoAcceptsWithoutDuplicateRows() async throws {
        try await withApp { app, tester in
            let alice = try await TestAppFactory.seedUser(on: app, username: "ReciprocalA")
            let bob = try await TestAppFactory.seedUser(on: app, username: "ReciprocalB")

            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/friends",
                token: alice.token,
                body: AddFriendRequest(username: bob.username)
            )
            let secondAddResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/friends",
                token: bob.token,
                body: AddFriendRequest(username: "reciprocala")
            )

            let accepted = try TestAppFactory.decode(FriendResponse.self, from: secondAddResponse)
            let friendships = try await FriendshipModel.query(on: app.db).all()

            XCTAssertEqual(secondAddResponse.status, .ok)
            XCTAssertEqual(accepted.status, "accepted")
            XCTAssertEqual(friendships.count, 1)
            XCTAssertEqual(friendships.first?.status, "accepted")
        }
    }

    func testBlockingUserRemovesFriendshipAndHidesSearchResults() async throws {
        try await withApp { app, tester in
            let alice = try await TestAppFactory.seedUser(on: app, username: "BlockAlice")
            let bob = try await TestAppFactory.seedUser(on: app, username: "BlockBob")
            try await TestAppFactory.seedAcceptedFriendship(on: app, between: alice, and: bob)

            let blockResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/users/\(bob.id)/block",
                token: alice.token
            )
            let aliceFriendsResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/friends",
                token: alice.token
            )
            let bobFriendsResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/friends",
                token: bob.token
            )
            let aliceSearchResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/users/search?q=blockbob",
                token: alice.token
            )
            let bobSearchResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/users/search?q=blockalice",
                token: bob.token
            )

            let aliceFriends = try TestAppFactory.decode([FriendResponse].self, from: aliceFriendsResponse)
            let bobFriends = try TestAppFactory.decode([FriendResponse].self, from: bobFriendsResponse)
            let aliceSearch = try TestAppFactory.decode([User].self, from: aliceSearchResponse)
            let bobSearch = try TestAppFactory.decode([User].self, from: bobSearchResponse)

            XCTAssertEqual(blockResponse.status, .noContent)
            XCTAssertTrue(aliceFriends.isEmpty)
            XCTAssertTrue(bobFriends.isEmpty)
            XCTAssertTrue(aliceSearch.isEmpty)
            XCTAssertTrue(bobSearch.isEmpty)
        }
    }

    func testNudgeRequiresAcceptedFriendshipAndReturnsSentStatus() async throws {
        try await withApp { app, tester in
            let alice = try await TestAppFactory.seedUser(on: app, username: "NudgeAlice")
            let bob = try await TestAppFactory.seedUser(on: app, username: "NudgeBob")

            let forbiddenResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/friends/\(bob.id)/nudge",
                token: alice.token
            )

            try await TestAppFactory.seedAcceptedFriendship(on: app, between: alice, and: bob)
            let sentResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/friends/\(bob.id)/nudge",
                token: alice.token
            )
            let sent = try TestAppFactory.decode(NudgeResponse.self, from: sentResponse)

            XCTAssertEqual(forbiddenResponse.status, .forbidden)
            XCTAssertEqual(sentResponse.status, .ok)
            XCTAssertEqual(sent.status, "nudge sent")
        }
    }

    func testPresenceHeartbeatControlsFriendOnlineStatus() async throws {
        try await withApp { app, tester in
            let alice = try await TestAppFactory.seedUser(on: app, username: "PresenceAlice")
            let bob = try await TestAppFactory.seedUser(on: app, username: "PresenceBob")
            try await TestAppFactory.seedAcceptedFriendship(on: app, between: alice, and: bob)

            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/users/me",
                token: bob.token
            )
            let afterOrdinaryRequest = try await UserModel.find(bob.id, on: app.db)
            XCTAssertNil(afterOrdinaryRequest?.lastSeenAt)

            let heartbeatResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/users/me/presence",
                token: bob.token,
                body: PresenceUpdateRequest(isActive: true)
            )
            var friendsResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/friends",
                token: alice.token
            )
            var friends = try TestAppFactory.decode([FriendResponse].self, from: friendsResponse)
            XCTAssertEqual(heartbeatResponse.status, .noContent)
            XCTAssertEqual(friends.first(where: { $0.id == bob.id })?.presence, .online)

            let inactiveResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/users/me/presence",
                token: bob.token,
                body: PresenceUpdateRequest(isActive: false)
            )
            friendsResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/friends",
                token: alice.token
            )
            friends = try TestAppFactory.decode([FriendResponse].self, from: friendsResponse)
            let inactiveBob = friends.first(where: { $0.id == bob.id })
            XCTAssertEqual(inactiveResponse.status, .noContent)
            XCTAssertEqual(inactiveBob?.presence, .offline)
            XCTAssertNotNil(inactiveBob?.lastActiveAt)

            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/users/me/presence",
                token: bob.token,
                body: PresenceUpdateRequest(isActive: true)
            )
            let storedBob = try await UserModel.find(bob.id, on: app.db)
            let bobModel = try XCTUnwrap(storedBob)
            bobModel.presenceExpiresAt = Date().addingTimeInterval(-1)
            try await bobModel.save(on: app.db)

            friendsResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/friends",
                token: alice.token
            )
            friends = try TestAppFactory.decode([FriendResponse].self, from: friendsResponse)
            XCTAssertEqual(friends.first(where: { $0.id == bob.id })?.presence, .offline)
        }
    }

    func testFriendPresenceOnlyCountsActiveUnexpiredLockedRoomsAsUnplugged() async throws {
        try await withApp { app, tester in
            let alice = try await TestAppFactory.seedUser(on: app, username: "RoomPresenceAlice")
            let host = try await TestAppFactory.seedUser(on: app, username: "RoomPresenceHost")
            let bob = try await TestAppFactory.seedUser(on: app, username: "RoomPresenceBob")
            try await TestAppFactory.seedAcceptedFriendship(on: app, between: alice, and: bob)

            let createResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions",
                token: host.token,
                body: CreateSessionRequest(title: "Presence", durationSeconds: 1_800)
            )
            let created = try TestAppFactory.decode(SessionResponse.self, from: createResponse)
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.session.code)/join",
                token: bob.token
            )
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/start",
                token: host.token
            )

            var friendsResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/friends",
                token: alice.token
            )
            var friends = try TestAppFactory.decode([FriendResponse].self, from: friendsResponse)
            XCTAssertEqual(friends.first(where: { $0.id == bob.id })?.presence, .unplugged)

            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/leave",
                token: bob.token
            )
            friendsResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/friends",
                token: alice.token
            )
            friends = try TestAppFactory.decode([FriendResponse].self, from: friendsResponse)
            XCTAssertNotEqual(friends.first(where: { $0.id == bob.id })?.presence, .unplugged)

            let expiredRoom = RoomModel(roomOwner: host.id, title: "Expired", durationSeconds: 60)
            expiredRoom.lockedAt = Date().addingTimeInterval(-3_600)
            try await expiredRoom.save(on: app.db)
            let expiredMember = MemberModel(userID: bob.id, roomID: try expiredRoom.requireID())
            try await expiredMember.save(on: app.db)

            friendsResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/friends",
                token: alice.token
            )
            friends = try TestAppFactory.decode([FriendResponse].self, from: friendsResponse)
            XCTAssertNotEqual(friends.first(where: { $0.id == bob.id })?.presence, .unplugged)
        }
    }

    func testJailbreakReportMarksParticipantJailbroken() async throws {
        try await withApp { app, tester in
            let host = try await TestAppFactory.seedUser(on: app, username: "JailbreakHost")
            let participant = try await TestAppFactory.seedUser(on: app, username: "JailbreakParticipant")

            let createResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions",
                token: host.token,
                body: CreateSessionRequest(title: "Jailbreak", durationSeconds: 1_800)
            )
            let created = try TestAppFactory.decode(SessionResponse.self, from: createResponse)
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.session.code)/join",
                token: participant.token
            )
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/start",
                token: host.token
            )

            let reportResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/jailbreaks",
                token: participant.token,
                body: ReportJailbreakRequest(reason: "screen_time_auth_cleared")
            )
            let sessionResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/sessions/\(created.id)",
                token: host.token
            )
            let session = try TestAppFactory.decode(SessionResponse.self, from: sessionResponse)
            let member = try await MemberModel.query(on: app.db)
                .filter(\.$roomID == created.id)
                .filter(\.$userID == participant.id)
                .first()

            XCTAssertEqual(reportResponse.status, .noContent)
            XCTAssertEqual(session.participants.first(where: { $0.userID == participant.id })?.status, .jailbroken)
            XCTAssertEqual(member?.config, MemberModel.jailbreakConfig)
            XCTAssertTrue(member?.leftEarly ?? false)
            XCTAssertNotNil(member?.leftAt)
        }
    }

    func testSessionReadAndJailbreakReportsRequireMembership() async throws {
        try await withApp { app, tester in
            let host = try await TestAppFactory.seedUser(on: app, username: "PrivateHost")
            let participant = try await TestAppFactory.seedUser(on: app, username: "PrivateMember")
            let intruder = try await TestAppFactory.seedUser(on: app, username: "PrivateIntruder")

            let createResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions",
                token: host.token,
                body: CreateSessionRequest(title: "Private", durationSeconds: 1_800)
            )
            let created = try TestAppFactory.decode(SessionResponse.self, from: createResponse)
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.session.code)/join",
                token: participant.token
            )
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/start",
                token: host.token
            )

            let readResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/sessions/\(created.id)",
                token: intruder.token
            )
            let reportResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/jailbreaks",
                token: intruder.token,
                body: ReportJailbreakRequest(reason: SessionExitReason.screenTimeAuthorizationCleared)
            )

            XCTAssertEqual(readResponse.status, .forbidden)
            XCTAssertEqual(reportResponse.status, .forbidden)
        }
    }

    func testShieldAttemptsRequireMembershipAndThrottleNotifications() async throws {
        try await withApp { app, tester in
            let host = try await TestAppFactory.seedUser(on: app, username: "ShieldHost")
            let participant = try await TestAppFactory.seedUser(on: app, username: "ShieldMember")
            let intruder = try await TestAppFactory.seedUser(on: app, username: "ShieldIntruder")

            let createResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions",
                token: host.token,
                body: CreateSessionRequest(title: "Shielded", durationSeconds: 1_800)
            )
            let created = try TestAppFactory.decode(SessionResponse.self, from: createResponse)
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.session.code)/join",
                token: participant.token
            )
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/start",
                token: host.token
            )

            let intruderResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/shield-attempt",
                token: intruder.token,
                body: ShieldActionAttemptRequest()
            )
            let firstResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/shield-attempt",
                token: participant.token,
                body: ShieldActionAttemptRequest()
            )
            let secondResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/shield-attempt",
                token: participant.token,
                body: ShieldActionAttemptRequest()
            )
            let records = try await JailbreakModel.query(on: app.db)
                .filter(\.$sessionID == created.id)
                .filter(\.$userID == participant.id)
                .filter(\.$reason == SessionExitReason.shieldActionAttempt)
                .all()

            XCTAssertEqual(intruderResponse.status, .forbidden)
            XCTAssertEqual(firstResponse.status, .noContent)
            XCTAssertEqual(secondResponse.status, .noContent)
            XCTAssertEqual(records.count, 1)
        }
    }

    func testCoLockUnlimitedRequiresReadinessAndUnanimousRelease() async throws {
        try await withApp { app, tester in
            let first = try await TestAppFactory.seedUser(on: app, username: "CoLockFirst")
            let second = try await TestAppFactory.seedUser(on: app, username: "CoLockSecond")

            let createResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions",
                token: first.token,
                body: CreateSessionRequest(
                    title: "Co-Lock",
                    durationSeconds: nil,
                    lockMode: .coLock
                )
            )
            let created = try TestAppFactory.decode(SessionResponse.self, from: createResponse)
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.session.code)/join",
                token: second.token
            )

            let startBeforeReady = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/start",
                token: first.token
            )
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/co-lock/ready",
                token: first.token,
                body: CoLockReadyRequest(isReady: true)
            )
            let startBeforeEveryoneReady = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/start",
                token: second.token
            )
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/co-lock/ready",
                token: second.token,
                body: CoLockReadyRequest(isReady: true)
            )
            let startResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/start",
                token: second.token
            )
            let started = try TestAppFactory.decode(SessionResponse.self, from: startResponse)

            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/co-lock/release",
                token: first.token
            )
            let endBeforeApproval = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/end",
                token: first.token
            )
            let approveResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/co-lock/release/approve",
                token: second.token
            )
            let ended = try TestAppFactory.decode(SessionResponse.self, from: approveResponse)

            XCTAssertEqual(startBeforeReady.status, .conflict)
            XCTAssertEqual(startBeforeEveryoneReady.status, .conflict)
            XCTAssertEqual(startResponse.status, .ok)
            XCTAssertNil(started.session.durationSeconds)
            XCTAssertNil(started.session.endsAt)
            XCTAssertEqual(started.session.lockMode, .coLock)
            XCTAssertEqual(started.session.coLockStatus?.requiredApprovals, 2)
            XCTAssertEqual(endBeforeApproval.status, .conflict)
            XCTAssertEqual(approveResponse.status, .ok)
            XCTAssertEqual(ended.session.state, .ended)
        }
    }

    func testSessionLifecycleProducesHistoryStatsAndRecap() async throws {
        try await withApp { app, tester in
            let host = try await TestAppFactory.seedUser(on: app, username: "HostUser")
            let participant = try await TestAppFactory.seedUser(on: app, username: "ParticipantUser")

            let createResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions",
                token: host.token,
                body: CreateSessionRequest(title: "Focus", durationSeconds: 3_600)
            )
            let created = try TestAppFactory.decode(SessionResponse.self, from: createResponse)

            let joinResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.session.code)/join",
                token: participant.token
            )
            let startResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/start",
                token: host.token
            )
            let roomRecord = try await RoomModel.find(created.id, on: app.db)
            let room = try XCTUnwrap(roomRecord)
            room.lockedAt = Date().addingTimeInterval(-4_000)
            try await room.save(on: app.db)

            let endResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/end",
                token: host.token
            )
            let historyResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/sessions/history?limit=10",
                token: participant.token
            )
            let statsResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/users/me/stats",
                token: host.token
            )
            let recapResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/sessions/\(created.id)/recap",
                token: host.token
            )

            let joined = try TestAppFactory.decode(SessionResponse.self, from: joinResponse)
            let ended = try TestAppFactory.decode(SessionResponse.self, from: endResponse)
            let history = try TestAppFactory.decode([SessionHistoryResponse].self, from: historyResponse)
            let stats = try TestAppFactory.decode(UserStatsResponse.self, from: statsResponse)
            let recap = try TestAppFactory.decode(SessionRecapResponse.self, from: recapResponse)

            XCTAssertEqual(joined.participants.count, 2)
            XCTAssertEqual(startResponse.status, .ok)
            XCTAssertEqual(ended.session.state, .ended)
            XCTAssertEqual(history.count, 1)
            XCTAssertEqual(history.first?.participantCount, 2)
            XCTAssertFalse(history.first?.leftEarly ?? true)
            XCTAssertEqual(stats.totalSessions, 1)
            XCTAssertEqual(stats.totalMinutes, 60)
            XCTAssertEqual(stats.points, 27)
            XCTAssertEqual(recap.actualFocusedSeconds, 3_600)
            XCTAssertEqual(recap.participants.count, 2)
            XCTAssertTrue(recap.jailbreaks.isEmpty)
        }
    }

    func testExpiredLockedSessionAutoEndsOnFetch() async throws {
        try await withApp { app, tester in
            let host = try await TestAppFactory.seedUser(on: app, username: "TimerHost")

            let createResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions",
                token: host.token,
                body: CreateSessionRequest(title: "Timer", durationSeconds: 60)
            )
            let created = try TestAppFactory.decode(SessionResponse.self, from: createResponse)
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/start",
                token: host.token
            )

            let roomRecord = try await RoomModel.find(created.id, on: app.db)
            let room = try XCTUnwrap(roomRecord)
            let lockedAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 120)
            let expectedEndedAt = lockedAt.addingTimeInterval(60)
            room.lockedAt = lockedAt
            try await room.save(on: app.db)

            let getResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/sessions/\(created.id)",
                token: host.token
            )
            let listResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/sessions",
                token: host.token
            )
            let historyResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/sessions/history?limit=10",
                token: host.token
            )

            let fetched = try TestAppFactory.decode(SessionResponse.self, from: getResponse)
            let active = try TestAppFactory.decode([SessionResponse].self, from: listResponse)
            let history = try TestAppFactory.decode([SessionHistoryResponse].self, from: historyResponse)

            XCTAssertEqual(fetched.session.state, .ended)
            XCTAssertEqual(try XCTUnwrap(fetched.session.endedAt).timeIntervalSince1970, expectedEndedAt.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertTrue(active.isEmpty)
            XCTAssertEqual(history.count, 1)
            XCTAssertFalse(history.first?.leftEarly ?? true)
            XCTAssertEqual(history.first?.actualFocusedSeconds, 60)
        }
    }

    func testUnlimitedSessionStatsUseElapsedFocusedTime() async throws {
        try await withApp { app, tester in
            let host = try await TestAppFactory.seedUser(on: app, username: "UnlimitedHost")

            let createResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions",
                token: host.token,
                body: CreateSessionRequest(title: "Unlimited", durationSeconds: nil)
            )
            let created = try TestAppFactory.decode(SessionResponse.self, from: createResponse)

            let startResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/start",
                token: host.token
            )
            let roomRecord = try await RoomModel.find(created.id, on: app.db)
            let room = try XCTUnwrap(roomRecord)
            room.lockedAt = Date().addingTimeInterval(-125)
            try await room.save(on: app.db)

            let endResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/end",
                token: host.token
            )
            let statsResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/users/me/stats",
                token: host.token
            )
            let recapResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/sessions/\(created.id)/recap",
                token: host.token
            )
            let historyResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/sessions/history?limit=10",
                token: host.token
            )

            let ended = try TestAppFactory.decode(SessionResponse.self, from: endResponse)
            let stats = try TestAppFactory.decode(UserStatsResponse.self, from: statsResponse)
            let recap = try TestAppFactory.decode(SessionRecapResponse.self, from: recapResponse)
            let history = try TestAppFactory.decode([SessionHistoryResponse].self, from: historyResponse)

            XCTAssertEqual(startResponse.status, .ok)
            XCTAssertEqual(ended.session.state, .ended)
            XCTAssertNil(recap.durationSeconds)
            XCTAssertGreaterThanOrEqual(recap.actualFocusedSeconds, 120)
            XCTAssertLessThanOrEqual(recap.actualFocusedSeconds, 130)
            XCTAssertEqual(stats.totalSessions, 1)
            XCTAssertEqual(stats.totalMinutes, recap.actualFocusedSeconds / 60)
            XCTAssertEqual(history.first?.actualFocusedSeconds, recap.actualFocusedSeconds)
        }
    }

    func testMementoMetadataAndPhotosArePostSessionOnly() async throws {
        try await withApp { app, tester in
            let host = try await TestAppFactory.seedUser(on: app, username: "MementoHost")
            let weather = SessionWeatherSnapshot(
                summary: "Cloudy",
                temperatureFahrenheit: 62,
                conditionSymbol: "cloud.fill",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )

            let createResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions",
                token: host.token,
                body: CreateSessionRequest(
                    title: "Memento",
                    durationSeconds: 1_800,
                    description: "should not be saved",
                    latitude: 1,
                    longitude: 2,
                    weather: weather
                )
            )
            let created = try TestAppFactory.decode(SessionResponse.self, from: createResponse)
            XCTAssertNil(created.session.description)
            XCTAssertNil(created.session.latitude)
            XCTAssertNil(created.session.weather)

            let preEndMetadata = try await TestAppFactory.sendRequest(
                with: tester,
                .PATCH,
                "/sessions/\(created.id)/metadata",
                token: host.token,
                body: SessionMetadataRequest(description: "Library grind")
            )
            let preEndPhoto = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/photos",
                token: host.token,
                body: UploadSessionPhotoRequest(
                    imageData: Data(repeating: 7, count: 24_000),
                    thumbnailData: Data(repeating: 3, count: 512),
                    mimeType: "image/jpeg"
                )
            )
            XCTAssertEqual(preEndMetadata.status, .conflict)
            XCTAssertEqual(preEndPhoto.status, .conflict)

            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/start",
                token: host.token
            )
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/end",
                token: host.token
            )

            let metadataResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .PATCH,
                "/sessions/\(created.id)/metadata",
                token: host.token,
                body: SessionMetadataRequest(
                    description: "Library grind",
                    latitude: 37.3349,
                    longitude: -122.009,
                    weather: weather
                )
            )
            let photoResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/photos",
                token: host.token,
                body: UploadSessionPhotoRequest(
                    imageData: Data(repeating: 9, count: 24_000),
                    thumbnailData: Data(repeating: 4, count: 512),
                    mimeType: "image/jpeg"
                )
            )
            let recapResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/sessions/\(created.id)/recap",
                token: host.token
            )

            let metadata = try TestAppFactory.decode(SessionResponse.self, from: metadataResponse)
            let photo = try TestAppFactory.decode(SessionMemoryPhotoResponse.self, from: photoResponse)
            let recap = try TestAppFactory.decode(SessionRecapResponse.self, from: recapResponse)

            XCTAssertEqual(metadata.session.description, "Library grind")
            XCTAssertEqual(metadata.session.latitude, 37.3349)
            XCTAssertEqual(metadata.session.weather?.summary, "Cloudy")
            XCTAssertEqual(photo.byteCount, 24_000)
            XCTAssertEqual(recap.description, "Library grind")
            XCTAssertEqual(recap.memoryPhotos.count, 1)
            XCTAssertEqual(recap.memoryPhotos.first?.thumbnailData?.count, 512)
        }
    }

    func testParticipantLeaveMarksEarlyExitInHistoryAndRecap() async throws {
        try await withApp { app, tester in
            let host = try await TestAppFactory.seedUser(on: app, username: "LeaveHost")
            let participant = try await TestAppFactory.seedUser(on: app, username: "LeaveParticipant")

            let createResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions",
                token: host.token,
                body: CreateSessionRequest(title: "Short Session", durationSeconds: 1_800)
            )
            let created = try TestAppFactory.decode(SessionResponse.self, from: createResponse)

            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.session.code)/join",
                token: participant.token
            )
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/start",
                token: host.token
            )
            let roomRecord = try await RoomModel.find(created.id, on: app.db)
            let room = try XCTUnwrap(roomRecord)
            room.lockedAt = Date().addingTimeInterval(-900)
            try await room.save(on: app.db)

            let leaveResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/leave",
                token: participant.token
            )
            _ = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/sessions/\(created.id)/end",
                token: host.token
            )
            let historyResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/sessions/history?limit=10",
                token: participant.token
            )
            let statsResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/users/me/stats",
                token: participant.token
            )
            let recapResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/sessions/\(created.id)/recap",
                token: host.token
            )

            let history = try TestAppFactory.decode([SessionHistoryResponse].self, from: historyResponse)
            let stats = try TestAppFactory.decode(UserStatsResponse.self, from: statsResponse)
            let recap = try TestAppFactory.decode(SessionRecapResponse.self, from: recapResponse)

            XCTAssertEqual(leaveResponse.status, .noContent)
            XCTAssertEqual(history.count, 1)
            XCTAssertTrue(history.first?.leftEarly ?? false)
            XCTAssertEqual(history.first?.leaveReason, "left_voluntarily")
            XCTAssertEqual(stats.earlyLeaveCount, 1)
            XCTAssertEqual(recap.jailbreaks.count, 1)
            XCTAssertEqual(recap.jailbreaks.first?.userID, participant.id)
            XCTAssertEqual(recap.jailbreaks.first?.reason, "left_voluntarily")
        }
    }
}

private extension ServerTests {
    func withApp(
        _ run: (Application, any XCTApplicationTester) async throws -> Void
    ) async throws {
        let app = try await TestAppFactory.make()
        do {
            let tester = try app.testable()
            try await run(app, tester)
            try await app.asyncShutdown()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
    }
}
