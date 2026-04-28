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
    private var loadToken = 0

    // Report flow state
    var reportTarget: FriendResponse?

    // The view still reads `visible*` names; keep them as passthroughs so the
    // view stays untouched. A fresh reload after every mutation is the single
    // source of truth — no optimistic dictionary to get out of sync with it.
    var visibleFriends: [FriendResponse] { friends }
    var visibleIncomingRequests: [FriendResponse] { incomingRequests }
    var visibleOutgoingRequests: [FriendResponse] { outgoingRequests }

    var excludedAddFriendIDs: Set<UUID> {
        Set(friends.map(\.id))
            .union(incomingRequests.map(\.id))
            .union(outgoingRequests.map(\.id))
    }

    var filteredFriends: [FriendResponse] {
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
            self.error = "Could not load friends"
        }

        if token == loadToken { isLoading = false }
        return token == loadToken
    }

    func addFriend(service: FriendAPIService) async -> Bool {
        let trimmed = addFriendUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        do {
            _ = try await service.addFriend(username: trimmed)
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

        do {
            _ = try await service.acceptRequest(friendID: requestID)
        } catch {
            self.error = "Failed to accept friend request"
        }
        await load(service: service, force: true)
    }

    func rejectRequest(service: FriendAPIService, requestID: UUID) async {
        guard rejectingRequestIDs.insert(requestID).inserted else { return }
        defer { rejectingRequestIDs.remove(requestID) }

        do {
            try await service.rejectRequest(friendID: requestID)
        } catch {
            self.error = "Failed to reject friend request"
        }
        await load(service: service, force: true)
    }

    /// Cancel an outgoing friend request. Uses the same reject endpoint on the
    /// server (which deletes pending rows regardless of direction once it matches).
    func cancelOutgoingRequest(service: FriendAPIService, targetID: UUID) async {
        guard cancellingRequestIDs.insert(targetID).inserted else { return }
        defer { cancellingRequestIDs.remove(targetID) }

        do {
            try await service.rejectRequest(friendID: targetID)
        } catch {
            self.error = "Failed to cancel request"
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
        let acceptedFriends = uniquedByID(friendsList.map { $0.withStatus("accepted") })
        let acceptedIDs = Set(acceptedFriends.map(\.id))

        friends = acceptedFriends
        incomingRequests = uniquedByID(incomingList)
            .filter { !acceptedIDs.contains($0.id) }
        outgoingRequests = uniquedByID(outgoingList)
            .filter { !acceptedIDs.contains($0.id) }
    }

    private func uniquedByID(_ responses: [FriendResponse]) -> [FriendResponse] {
        var seen: Set<UUID> = []
        var unique: [FriendResponse] = []
        for response in responses where seen.insert(response.id).inserted {
            unique.append(response)
        }
        return unique
    }
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
