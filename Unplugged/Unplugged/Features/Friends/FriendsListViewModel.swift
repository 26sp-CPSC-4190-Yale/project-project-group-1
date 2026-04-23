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

    // Report flow state
    var reportTarget: FriendResponse?

    var visibleIncomingRequests: [FriendResponse] {
        // Anyone already present in `friends` is — by definition — no longer a
        // pending request. A stale pending row from a prior race can cause the
        // server to keep returning them here; filter defensively so the user
        // doesn't see Accept/× for someone who's already their friend.
        let friendIDs = Set(friends.map(\.id))
        return incomingRequests.filter {
            !resolvedIncomingIDs.contains($0.id) && !friendIDs.contains($0.id)
        }
    }

    var visibleOutgoingRequests: [FriendResponse] {
        let friendIDs = Set(friends.map(\.id))
        return outgoingRequests.filter {
            !resolvedOutgoingIDs.contains($0.id) && !friendIDs.contains($0.id)
        }
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

    func load(service: FriendAPIService) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            async let fetchFriends = service.listFriends()
            async let fetchIncoming = service.listIncoming()
            async let fetchOutgoing = service.listOutgoing()

            let friendsList = try await fetchFriends
            let incomingList = try await fetchIncoming
            let outgoingList = try await fetchOutgoing

            self.friends = friendsList
            self.incomingRequests = incomingList
            self.outgoingRequests = outgoingList

            // Drop local overrides for any IDs the server has already reconciled
            // (i.e., no longer returns as pending). Keep overrides for anything
            // still pending so a stale fetch that completed after a tap doesn't
            // re-surface the button the user just dismissed.
            let incomingIDs = Set(incomingList.map(\.id))
            resolvedIncomingIDs = resolvedIncomingIDs.intersection(incomingIDs)
            let outgoingIDs = Set(outgoingList.map(\.id))
            resolvedOutgoingIDs = resolvedOutgoingIDs.intersection(outgoingIDs)
        } catch is CancellationError {
            // View torn down or refresh superseded — not a user-facing error.
        } catch {
            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            self.error = "Could not load friends"
        }
        isLoading = false
    }

    func addFriend(service: FriendAPIService) async {
        let trimmed = addFriendUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await service.addFriend(username: trimmed)
            addFriendUsername = ""
            showAddFriend = false
            // Background refresh -- don't block the caller
            Task { await load(service: service) }
        } catch {
            self.error = "Could not send friend request"
        }
    }

    func acceptRequest(service: FriendAPIService, requestID: UUID) async {
        // Flag the request as resolved so the view hides the Accept button
        // immediately. We intentionally do NOT mutate incomingRequests here
        // — an in-flight load() finishing after the tap would otherwise
        // overwrite the removal with stale pre-accept data and re-surface
        // the button. Drop a placeholder into friends so the row reappears
        // there until the reconciling load() lands with the real record.
        resolvedIncomingIDs.insert(requestID)
        if let placeholder = incomingRequests.first(where: { $0.id == requestID }),
           !friends.contains(where: { $0.id == placeholder.id }) {
            friends.append(FriendResponse(
                id: placeholder.id,
                username: placeholder.username,
                status: "accepted",
                presence: placeholder.presence,
                hoursUnplugged: placeholder.hoursUnplugged,
                lastActiveAt: placeholder.lastActiveAt
            ))
        }
        do {
            _ = try await service.acceptRequest(friendID: requestID)
            await load(service: service)
        } catch {
            // Server said no — unhide the row so the user can try again.
            resolvedIncomingIDs.remove(requestID)
            friends.removeAll { $0.id == requestID }
            self.error = "Failed to accept friend request"
            await load(service: service)
        }
    }

    func rejectRequest(service: FriendAPIService, requestID: UUID) async {
        resolvedIncomingIDs.insert(requestID)
        do {
            try await service.rejectRequest(friendID: requestID)
            await load(service: service)
        } catch {
            resolvedIncomingIDs.remove(requestID)
            self.error = "Failed to reject friend request"
            await load(service: service)
        }
    }

    /// Cancel an outgoing friend request. Uses the same reject endpoint on the
    /// server (which deletes pending rows regardless of direction once it matches).
    func cancelOutgoingRequest(service: FriendAPIService, targetID: UUID) async {
        resolvedOutgoingIDs.insert(targetID)
        do {
            try await service.rejectRequest(friendID: targetID)
            await load(service: service)
        } catch {
            resolvedOutgoingIDs.remove(targetID)
            self.error = "Failed to cancel request"
            await load(service: service)
        }
    }

    func blockUser(id: UUID, user: UserAPIService, friends friendsService: FriendAPIService) async {
        // Optimistically remove so the row disappears immediately; refresh covers any drift.
        self.friends.removeAll { $0.id == id }
        self.incomingRequests.removeAll { $0.id == id }
        self.outgoingRequests.removeAll { $0.id == id }
        do {
            try await user.blockUser(id: id)
            await load(service: friendsService)
        } catch {
            self.error = "Could not block user"
            await load(service: friendsService)
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
}
