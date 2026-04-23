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

    // Request IDs that the user has already resolved locally but whose server
    // reconciliation might not have landed yet. The view filters them out of
    // incomingRequests / outgoingRequests so a stale in-flight load() cannot
    // re-surface an Accept or Cancel button the user just dismissed.
    private(set) var resolvedIncomingIDs: Set<UUID> = []
    private(set) var resolvedOutgoingIDs: Set<UUID> = []
    private var acceptingRequestIDs: Set<UUID> = []
    private var loadGeneration = 0

    // Report flow state
    var reportTarget: FriendResponse?

    var visibleIncomingRequests: [FriendResponse] {
        incomingRequests.filter { !resolvedIncomingIDs.contains($0.id) }
    }

    var visibleOutgoingRequests: [FriendResponse] {
        outgoingRequests.filter { !resolvedOutgoingIDs.contains($0.id) }
    }

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

    @discardableResult
    func load(service: FriendAPIService, force: Bool = false) async -> Bool {
        guard force || !isLoading else { return false }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        error = nil
        do {
            async let fetchFriends = service.listFriends()
            async let fetchIncoming = service.listIncoming()
            async let fetchOutgoing = service.listOutgoing()

            let friendsList = try await fetchFriends
            let incomingList = try await fetchIncoming
            let outgoingList = try await fetchOutgoing

            guard generation == loadGeneration else { return false }

            applySnapshot(
                friends: friendsList,
                incoming: incomingList,
                outgoing: outgoingList
            )
        } catch is CancellationError {
            // View torn down or refresh superseded — not a user-facing error.
            if generation == loadGeneration {
                isLoading = false
            }
            return false
        } catch {
            guard !Task.isCancelled else {
                if generation == loadGeneration {
                    isLoading = false
                }
                return false
            }
            guard generation == loadGeneration else { return false }
            self.error = "Could not load friends"
        }
        if generation == loadGeneration {
            isLoading = false
        }
        return generation == loadGeneration
    }

    func addFriend(service: FriendAPIService) async {
        let trimmed = addFriendUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let response = try await service.addFriend(username: trimmed)
            addFriendUsername = ""
            showAddFriend = false
            if response.status == "accepted" {
                upsertAcceptedFriend(response)
            } else {
                upsertOutgoingRequest(response)
            }
            // Background refresh; the optimistic row keeps the UI current while
            // the server snapshot catches up.
            Task { await load(service: service, force: true) }
        } catch {
            self.error = "Could not send friend request"
        }
    }

    func acceptRequest(service: FriendAPIService, requestID: UUID) async {
        guard acceptingRequestIDs.insert(requestID).inserted else { return }
        defer { acceptingRequestIDs.remove(requestID) }

        let originalRequest = incomingRequests.first(where: { $0.id == requestID })
        if let placeholder = originalRequest {
            upsertAcceptedFriend(placeholder)
        } else {
            resolvedIncomingIDs.insert(requestID)
            resolvedOutgoingIDs.insert(requestID)
            incomingRequests.removeAll { $0.id == requestID }
            outgoingRequests.removeAll { $0.id == requestID }
        }

        do {
            let accepted = try await service.acceptRequest(friendID: requestID)
            upsertAcceptedFriend(accepted)
            await load(service: service, force: true)
        } catch {
            let refreshed = await load(service: service, force: true)
            if !refreshed || !friends.contains(where: { $0.id == requestID }) {
                friends.removeAll { $0.id == requestID }
                if let originalRequest,
                   !incomingRequests.contains(where: { $0.id == originalRequest.id }) {
                    incomingRequests.append(originalRequest)
                }
                resolvedIncomingIDs.remove(requestID)
                resolvedOutgoingIDs.remove(requestID)
                if refreshed {
                    self.error = "Failed to accept friend request"
                } else {
                    self.error = "Could not refresh friends"
                }
            }
        }
    }

    func rejectRequest(service: FriendAPIService, requestID: UUID) async {
        resolvedIncomingIDs.insert(requestID)
        incomingRequests.removeAll { $0.id == requestID }
        do {
            try await service.rejectRequest(friendID: requestID)
            await load(service: service, force: true)
        } catch {
            resolvedIncomingIDs.remove(requestID)
            self.error = "Failed to reject friend request"
            await load(service: service, force: true)
        }
    }

    /// Cancel an outgoing friend request. Uses the same reject endpoint on the
    /// server (which deletes pending rows regardless of direction once it matches).
    func cancelOutgoingRequest(service: FriendAPIService, targetID: UUID) async {
        resolvedOutgoingIDs.insert(targetID)
        outgoingRequests.removeAll { $0.id == targetID }
        do {
            try await service.rejectRequest(friendID: targetID)
            await load(service: service, force: true)
        } catch {
            resolvedOutgoingIDs.remove(targetID)
            self.error = "Failed to cancel request"
            await load(service: service, force: true)
        }
    }

    func blockUser(id: UUID, user: UserAPIService, friends friendsService: FriendAPIService) async {
        // Optimistically remove so the row disappears immediately; refresh covers any drift.
        self.friends.removeAll { $0.id == id }
        self.incomingRequests.removeAll { $0.id == id }
        self.outgoingRequests.removeAll { $0.id == id }
        do {
            try await user.blockUser(id: id)
            await load(service: friendsService, force: true)
        } catch {
            self.error = "Could not block user"
            await load(service: friendsService, force: true)
        }
    }

    func reportUser(id: UUID, reason: String, details: String, user: UserAPIService) async {
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await user.reportUser(id: id, reason: reason, details: trimmedDetails.isEmpty ? nil : trimmedDetails)
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

        let incomingIDs = Set(incomingRequests.map(\.id))
        resolvedIncomingIDs = resolvedIncomingIDs.intersection(incomingIDs)
        let outgoingIDs = Set(outgoingRequests.map(\.id))
        resolvedOutgoingIDs = resolvedOutgoingIDs.intersection(outgoingIDs)
    }

    private func upsertAcceptedFriend(_ friend: FriendResponse) {
        let accepted = friend.withStatus("accepted")
        resolvedIncomingIDs.insert(accepted.id)
        resolvedOutgoingIDs.insert(accepted.id)
        incomingRequests.removeAll { $0.id == accepted.id }
        outgoingRequests.removeAll { $0.id == accepted.id }
        if let index = friends.firstIndex(where: { $0.id == accepted.id }) {
            friends[index] = accepted
        } else {
            friends.append(accepted)
        }
    }

    private func upsertOutgoingRequest(_ request: FriendResponse) {
        guard !friends.contains(where: { $0.id == request.id }),
              !outgoingRequests.contains(where: { $0.id == request.id }) else { return }
        outgoingRequests.append(request)
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
