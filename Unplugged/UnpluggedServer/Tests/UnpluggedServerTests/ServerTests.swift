import Fluent
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
            XCTAssertEqual(found.map(\.id), [alpha.id])
            XCTAssertEqual(storedUser.deviceToken, "aabbccddeeff00112233445566778899")
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

    func testGroupLifecycleEnforcesOwnerPermissions() async throws {
        try await withApp { app, tester in
            let owner = try await TestAppFactory.seedUser(on: app, username: "GroupOwner")
            let member = try await TestAppFactory.seedUser(on: app, username: "GroupMember")

            let createResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/groups",
                token: owner.token,
                body: CreateGroupRequest(name: "Study Crew")
            )
            let created = try TestAppFactory.decode(GroupResponse.self, from: createResponse)

            let forbiddenBeforeAdd = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/groups/\(created.id)",
                token: member.token
            )
            let addMemberResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .POST,
                "/groups/\(created.id)/members",
                token: owner.token,
                body: AddGroupMemberRequest(userID: member.id)
            )
            let memberGetResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/groups/\(created.id)",
                token: member.token
            )
            let memberDeleteGroupResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .DELETE,
                "/groups/\(created.id)",
                token: member.token
            )
            let memberRemoveSelfResponse = try await TestAppFactory.sendRequest(
                with: tester,
                .DELETE,
                "/groups/\(created.id)/members/\(member.id)",
                token: member.token
            )
            let forbiddenAfterRemoval = try await TestAppFactory.sendRequest(
                with: tester,
                .GET,
                "/groups/\(created.id)",
                token: member.token
            )

            let updated = try TestAppFactory.decode(GroupResponse.self, from: addMemberResponse)
            let visibleToMember = try TestAppFactory.decode(GroupResponse.self, from: memberGetResponse)

            XCTAssertEqual(forbiddenBeforeAdd.status, .forbidden)
            XCTAssertEqual(updated.members.count, 2)
            XCTAssertEqual(visibleToMember.members.count, 2)
            XCTAssertEqual(memberDeleteGroupResponse.status, .forbidden)
            XCTAssertEqual(memberRemoveSelfResponse.status, .noContent)
            XCTAssertEqual(forbiddenAfterRemoval.status, .forbidden)
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
            XCTAssertEqual(stats.points, 72)
            XCTAssertEqual(recap.actualFocusedSeconds, 3_600)
            XCTAssertEqual(recap.participants.count, 2)
            XCTAssertTrue(recap.jailbreaks.isEmpty)
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
