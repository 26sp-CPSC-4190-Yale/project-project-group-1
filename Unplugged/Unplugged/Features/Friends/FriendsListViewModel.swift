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
    var searchText = ""
    var showAddFriend = false
    var addFriendUsername = ""
    var isLoading = false
    var error: String?

    // Report flow state
    var reportTarget: FriendResponse?

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

            self.friends = try await fetchFriends
            self.incomingRequests = try await fetchIncoming
        } catch {
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
        do {
            _ = try await service.acceptRequest(friendID: requestID)
            await load(service: service)
        } catch {
            self.error = "Failed to accept friend request"
        }
    }

    func rejectRequest(service: FriendAPIService, requestID: UUID) async {
        do {
            try await service.rejectRequest(friendID: requestID)
            await load(service: service)
        } catch {
            self.error = "Failed to reject friend request"
        }
    }

    func blockUser(id: UUID, user: UserAPIService, friends friendsService: FriendAPIService) async {
        // Optimistically remove so the row disappears immediately; refresh covers any drift.
        self.friends.removeAll { $0.id == id }
        self.incomingRequests.removeAll { $0.id == id }
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
