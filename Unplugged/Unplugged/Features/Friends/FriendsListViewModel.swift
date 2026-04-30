//
//  FriendsListViewModel.swift
//  Unplugged.Features.Friends
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class FriendsListViewModel {
    var friends: [FriendResponse] = []
    var incomingRequests: [FriendResponse] = []
    var outgoingRequests: [FriendResponse] = []
    var searchText = ""
    var showAddFriend = false
    var addFriendUsername = ""
    var isLoading = false
    var error: String?

    private(set) var acceptingRequestIDs: Set<UUID> = []
    private(set) var rejectingRequestIDs: Set<UUID> = []
    private(set) var cancellingRequestIDs: Set<UUID> = []
    private(set) var nudgingFriendIDs: Set<UUID> = []
    private(set) var removingFriendIDs: Set<UUID> = []
    private var loadToken = 0
    private var locallyAcceptedFriends: [UUID: FriendResponse] = [:]
    private var locallyOutgoingRequests: [UUID: LocalFriendState] = [:]
    private let localOutgoingTTL: TimeInterval = 10

    // Report flow state
    var reportTarget: FriendResponse?

    // The view still reads `visible*` names; keep them as passthroughs so the
    // view stays untouched. A fresh reload after every mutation is the single
    // source of truth — no optimistic dictionary to get out of sync with it.
    var visibleFriends: [FriendResponse] { friends }
    var visibleIncomingRequests: [FriendResponse] {
        incomingRequests.filter {
            !acceptingRequestIDs.contains($0.id)
                && !rejectingRequestIDs.contains($0.id)
                && !hasAcceptedFriend(matching: $0)
        }
    }
    var visibleOutgoingRequests: [FriendResponse] {
        outgoingRequests.filter {
            !cancellingRequestIDs.contains($0.id)
                && !hasAcceptedFriend(matching: $0)
        }
    }

    var excludedAddFriendIDs: Set<UUID> {
        Set(friends.map(\.id))
            .union(incomingRequests.map(\.id))
            .union(outgoingRequests.map(\.id))
    }

    var filteredFriends: [FriendResponse] {
        AppLogger.measureMainThreadWork(
            "FriendsListViewModel.filteredFriends",
            category: .ui,
            context: ["friends": friends.count, "query_len": searchText.count],
            warnAfter: 0.02
        ) {
            let base = searchText.isEmpty
                ? friends
                : friends.filter { $0.username.localizedCaseInsensitiveContains(searchText) }
            return base.sorted { a, b in
                let lhs = sortRecency(for: a)
                let rhs = sortRecency(for: b)
                if lhs != rhs { return lhs > rhs }
                return a.username.localizedCaseInsensitiveCompare(b.username) == .orderedAscending
            }
        }
    }

    private func sortRecency(for friend: FriendResponse) -> Date {
        switch friend.presence {
        case .online, .unplugged: return .distantFuture
        case .offline:            return friend.lastActiveAt ?? .distantPast
        }
    }

    func isAccepting(requestID: UUID) -> Bool {
        acceptingRequestIDs.contains(requestID)
    }

    func isRejecting(requestID: UUID) -> Bool {
        rejectingRequestIDs.contains(requestID)
    }

    func isCancelling(requestID: UUID) -> Bool {
        cancellingRequestIDs.contains(requestID)
    }

    func isNudging(friendID: UUID) -> Bool {
        nudgingFriendIDs.contains(friendID)
    }

    func isRemovingFriend(friendID: UUID) -> Bool {
        removingFriendIDs.contains(friendID)
    }

    @discardableResult
    func load(service: FriendAPIService, force: Bool = false) async -> Bool {
        guard force || !isLoading else { return false }

        loadToken += 1
        let token = loadToken
        isLoading = true
        error = nil

        do {
            async let fetchFriends = service.listFriends()
            async let fetchIncoming = service.listIncoming()
            async let fetchOutgoing = service.listOutgoing()

            let (friendsList, incomingList, outgoingList) =
                try await (fetchFriends, fetchIncoming, fetchOutgoing)

            guard token == loadToken else { return false }
            applySnapshot(
                friends: friendsList,
                incoming: incomingList,
                outgoing: outgoingList
            )
        } catch is CancellationError {
            if token == loadToken { isLoading = false }
            return false
        } catch {
            guard !Task.isCancelled, token == loadToken else {
                if token == loadToken { isLoading = false }
                return false
            }
            if friends.isEmpty && incomingRequests.isEmpty && outgoingRequests.isEmpty {
                self.error = "Could not load friends"
            }
        }

        if token == loadToken { isLoading = false }
        return token == loadToken
    }

    func addFriend(service: FriendAPIService) async -> Bool {
        let trimmed = addFriendUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        do {
            let response = try await service.addFriend(username: trimmed)
            applyAddedFriendLocally(response)
            addFriendUsername = ""
            showAddFriend = false
            await load(service: service, force: true)
            return true
        } catch {
            self.error = "Could not send friend request"
            return false
        }
    }

    func acceptRequest(service: FriendAPIService, requestID: UUID) async {
        guard acceptingRequestIDs.insert(requestID).inserted else { return }
        defer { acceptingRequestIDs.remove(requestID) }

        let pendingRequest = incomingRequests.first { $0.id == requestID }

        do {
            let acceptedFriend = try await service.acceptRequest(friendID: requestID)
            applyAcceptedRequestLocally(acceptedFriend, fallbackRequest: pendingRequest)
            await load(service: service, force: true)
        } catch {
            self.error = "Failed to accept friend request"
        }
    }

    func rejectRequest(service: FriendAPIService, requestID: UUID) async {
        guard rejectingRequestIDs.insert(requestID).inserted else { return }
        defer { rejectingRequestIDs.remove(requestID) }

        let pendingRequest = incomingRequests.first { $0.id == requestID }

        do {
            try await service.rejectIncomingRequest(requestID: requestID)
            if let pendingRequest {
                removeIncomingRequest(matching: pendingRequest)
            } else {
                incomingRequests.removeAll { $0.id == requestID }
            }
            await load(service: service, force: true)
        } catch {
            self.error = "Failed to reject friend request"
        }
    }

    /// Cancel an outgoing friend request. Uses the same reject endpoint on the
    /// server (which deletes pending rows regardless of direction once it matches).
    func cancelOutgoingRequest(service: FriendAPIService, targetID: UUID) async {
        guard cancellingRequestIDs.insert(targetID).inserted else { return }
        defer { cancellingRequestIDs.remove(targetID) }

        let outgoingRequest = outgoingRequests.first { $0.id == targetID }

        do {
            try await service.cancelOutgoingRequest(targetID: targetID)
            if let outgoingRequest {
                removeOutgoingRequest(matching: outgoingRequest)
            } else {
                outgoingRequests.removeAll { $0.id == targetID }
            }
            await load(service: service, force: true)
        } catch {
            self.error = "Failed to cancel request"
        }
    }

    func nudge(service: FriendAPIService, friendID: UUID) async {
        guard nudgingFriendIDs.insert(friendID).inserted else { return }
        defer { nudgingFriendIDs.remove(friendID) }

        do {
            try await service.nudge(friendID: friendID)
        } catch {
            self.error = "Failed to send nudge"
        }
    }

    func removeFriend(service: FriendAPIService, friend: FriendResponse) async {
        guard removingFriendIDs.insert(friend.id).inserted else { return }
        defer { removingFriendIDs.remove(friend.id) }

        do {
            try await service.removeFriend(id: friend.id)
            removePendingRequests(matching: friend)
            removeLocalState(matching: friend)
            friends.removeAll { matches($0, friend) }
            NotificationCenter.default.post(name: .unpluggedFriendsDidChange, object: nil)
        } catch {
            self.error = "Failed to remove friend"
        }

        await load(service: service, force: true)
    }

    func blockUser(id: UUID, user: UserAPIService, friends friendsService: FriendAPIService) async {
        friends.removeAll { $0.id == id }
        incomingRequests.removeAll { $0.id == id }
        outgoingRequests.removeAll { $0.id == id }
        do {
            try await user.blockUser(id: id)
        } catch {
            self.error = "Could not block user"
        }
        await load(service: friendsService, force: true)
    }

    func reportUser(id: UUID, reason: String, details: String, user: UserAPIService) async {
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await user.reportUser(
                id: id,
                reason: reason,
                details: trimmedDetails.isEmpty ? nil : trimmedDetails
            )
        } catch {
            self.error = "Could not submit report"
        }
    }

    private func applySnapshot(
        friends friendsList: [FriendResponse],
        incoming incomingList: [FriendResponse],
        outgoing outgoingList: [FriendResponse]
    ) {
        let trace = AppLogger.beginMainThreadWork(
            "FriendsListViewModel.applySnapshot",
            category: .ui,
            context: [
                "friends": friendsList.count,
                "incoming": incomingList.count,
                "outgoing": outgoingList.count
            ],
            warnAfter: 0.03
        )
        defer { trace.end() }

        pruneExpiredLocalOutgoingRequests()

        let serverAcceptedFriends = uniquedByIdentity(friendsList.map { $0.withStatus("accepted") })
        let acceptedFriends = uniquedByIdentity(
            serverAcceptedFriends + locallyAcceptedFriends.values.map { $0.withStatus("accepted") }
        )
        let pendingIncoming = pendingRequests(incomingList, excluding: acceptedFriends)
        let pendingOutgoing = pendingRequests(
            outgoingList + locallyOutgoingRequests.values.map(\.friend),
            excluding: acceptedFriends
        )

        friends = acceptedFriends
        incomingRequests = pendingIncoming
        outgoingRequests = pendingOutgoing

        pruneLocalState(serverAcceptedFriends: serverAcceptedFriends, serverOutgoingRequests: outgoingList)
    }

    private func applyAddedFriendLocally(_ response: FriendResponse) {
        if normalizedStatus(response.status) == "accepted" {
            applyAcceptedRequestLocally(response, fallbackRequest: response)
        } else {
            let pending = response.withStatus("pending")
            outgoingRequests = mergeResponse(pending, into: outgoingRequests)
            locallyOutgoingRequests[pending.id] = LocalFriendState(friend: pending, createdAt: Date())
        }
    }

    private func applyAcceptedRequestLocally(
        _ acceptedFriend: FriendResponse,
        fallbackRequest: FriendResponse?
    ) {
        let accepted = acceptedFriend.withStatus("accepted")
        locallyAcceptedFriends[accepted.id] = accepted
        locallyOutgoingRequests.removeValue(forKey: accepted.id)
        friends = mergeFriend(accepted, into: friends)
        removePendingRequests(matching: accepted)
        if let fallbackRequest {
            removePendingRequests(matching: fallbackRequest)
        }
    }

    private func removePendingRequests(matching response: FriendResponse) {
        removeIncomingRequest(matching: response)
        removeOutgoingRequest(matching: response)
    }

    private func removeIncomingRequest(matching response: FriendResponse) {
        incomingRequests.removeAll { matches($0, response) }
    }

    private func removeOutgoingRequest(matching response: FriendResponse) {
        outgoingRequests.removeAll { matches($0, response) }
        locallyOutgoingRequests = locallyOutgoingRequests.filter { !matches($0.value.friend, response) }
    }

    private func mergeFriend(_ friend: FriendResponse, into currentFriends: [FriendResponse]) -> [FriendResponse] {
        mergeResponse(friend.withStatus("accepted"), into: currentFriends)
    }

    private func mergeResponse(_ response: FriendResponse, into currentResponses: [FriendResponse]) -> [FriendResponse] {
        var updatedResponses = currentResponses.filter { !matches($0, response) }
        updatedResponses.append(response)
        return updatedResponses
    }

    private func uniquedByIdentity(_ responses: [FriendResponse]) -> [FriendResponse] {
        var seenIDs: Set<UUID> = []
        var seenUsernames: Set<String> = []
        var unique: [FriendResponse] = []
        for response in responses {
            let username = normalizedUsername(response.username)
            guard !seenIDs.contains(response.id),
                  !seenUsernames.contains(username) else {
                continue
            }
            seenIDs.insert(response.id)
            seenUsernames.insert(username)
            unique.append(response)
        }
        return unique
    }

    private func pendingRequests(
        _ requests: [FriendResponse],
        excluding acceptedFriends: [FriendResponse]
    ) -> [FriendResponse] {
        uniquedByIdentity(requests).filter { request in
            normalizedStatus(request.status) != "accepted"
                && !acceptedFriends.contains { matches($0, request) }
        }
    }

    private func hasAcceptedFriend(matching response: FriendResponse) -> Bool {
        friends.contains { matches($0, response) }
    }

    private func pruneLocalState(
        serverAcceptedFriends: [FriendResponse],
        serverOutgoingRequests: [FriendResponse]
    ) {
        locallyAcceptedFriends = locallyAcceptedFriends.filter { _, local in
            !serverAcceptedFriends.contains { matches($0, local) }
        }
        locallyOutgoingRequests = locallyOutgoingRequests.filter { _, local in
            !serverAcceptedFriends.contains { matches($0, local.friend) }
                && !serverOutgoingRequests.contains { matches($0, local.friend) }
        }
    }

    private func pruneExpiredLocalOutgoingRequests() {
        let now = Date()
        locallyOutgoingRequests = locallyOutgoingRequests.filter {
            now.timeIntervalSince($0.value.createdAt) < localOutgoingTTL
        }
    }

    private func removeLocalState(matching response: FriendResponse) {
        locallyAcceptedFriends = locallyAcceptedFriends.filter { !matches($0.value, response) }
        locallyOutgoingRequests = locallyOutgoingRequests.filter { !matches($0.value.friend, response) }
    }

    private func matches(_ lhs: FriendResponse, _ rhs: FriendResponse) -> Bool {
        lhs.id == rhs.id || normalizedUsername(lhs.username) == normalizedUsername(rhs.username)
    }

    private func normalizedUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedStatus(_ status: String?) -> String? {
        status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct LocalFriendState {
    let friend: FriendResponse
    let createdAt: Date
}

private extension FriendResponse {
    func withStatus(_ status: String) -> FriendResponse {
        FriendResponse(
            id: id,
            username: username,
            status: status,
            presence: presence,
            hoursUnplugged: hoursUnplugged,
            lastActiveAt: lastActiveAt
        )
    }
}
