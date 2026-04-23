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
    private var loadRequestID = 0
    private var stateVersion = 0

    // Report flow state
    var reportTarget: FriendResponse?

    var visibleIncomingRequests: [FriendResponse] {
        incomingRequests
    }

    var visibleOutgoingRequests: [FriendResponse] {
        outgoingRequests
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
        guard force || !isLoading else {
            AppLogger.ui.debug(
                "friends load skipped while request already in flight",
                context: ["force": force]
            )
            return false
        }

        loadRequestID += 1
        let requestID = loadRequestID
        let versionAtStart = stateVersion
        isLoading = true
        error = nil
        AppLogger.ui.info(
            "friends load begin",
            context: [
                "request_id": requestID,
                "force": force,
                "state_version": versionAtStart
            ]
        )

        do {
            async let fetchFriends = service.listFriends()
            async let fetchIncoming = service.listIncoming()
            async let fetchOutgoing = service.listOutgoing()

            let friendsList = try await fetchFriends
            let incomingList = try await fetchIncoming
            let outgoingList = try await fetchOutgoing

            guard requestID == loadRequestID, versionAtStart == stateVersion else {
                if requestID == loadRequestID {
                    isLoading = false
                }
                AppLogger.ui.info(
                    "friends load discarded",
                    context: [
                        "request_id": requestID,
                        "state_version_start": versionAtStart,
                        "state_version_now": stateVersion,
                        "latest_request_id": loadRequestID
                    ]
                )
                return false
            }

            applySnapshot(
                friends: friendsList,
                incoming: incomingList,
                outgoing: outgoingList
            )
            AppLogger.ui.info(
                "friends load applied",
                context: [
                    "request_id": requestID,
                    "friends": friends.count,
                    "incoming": incomingRequests.count,
                    "outgoing": outgoingRequests.count
                ]
            )
        } catch is CancellationError {
            if requestID == loadRequestID {
                isLoading = false
            }
            AppLogger.ui.debug(
                "friends load cancelled",
                context: ["request_id": requestID]
            )
            return false
        } catch {
            guard !Task.isCancelled else {
                if requestID == loadRequestID {
                    isLoading = false
                }
                return false
            }
            guard requestID == loadRequestID, versionAtStart == stateVersion else { return false }
            AppLogger.ui.error(
                "friends load failed",
                error: error,
                context: [
                    "request_id": requestID,
                    "state_version": versionAtStart
                ]
            )
            self.error = "Could not load friends"
        }
        if requestID == loadRequestID {
            isLoading = false
        }
        return requestID == loadRequestID && versionAtStart == stateVersion
    }

    func addFriend(service: FriendAPIService) async -> Bool {
        let trimmed = addFriendUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        AppLogger.ui.info(
            "friend add begin",
            context: ["username": trimmed]
        )
        do {
            let response = try await service.addFriend(username: trimmed)
            advanceStateVersion()
            addFriendUsername = ""
            showAddFriend = false

            if response.status == "accepted" {
                upsertAcceptedFriend(response)
                AppLogger.ui.info(
                    "friend add auto-accepted",
                    context: [
                        "friend_id": response.id.uuidString,
                        "username": response.username
                    ]
                )
            } else {
                upsertOutgoingRequest(response)
                AppLogger.ui.info(
                    "friend add sent",
                    context: [
                        "friend_id": response.id.uuidString,
                        "username": response.username
                    ]
                )
            }

            Task { await load(service: service, force: true) }
            return true
        } catch {
            AppLogger.ui.error(
                "friend add failed",
                error: error,
                context: ["username": trimmed]
            )
            self.error = "Could not send friend request"
            return false
        }
    }

    func acceptRequest(service: FriendAPIService, requestID: UUID) async {
        guard acceptingRequestIDs.insert(requestID).inserted else {
            AppLogger.ui.debug(
                "friend accept ignored duplicate tap",
                context: ["friend_id": requestID.uuidString]
            )
            return
        }
        defer { acceptingRequestIDs.remove(requestID) }

        let originalRequest = incomingRequests.first(where: { $0.id == requestID })
        AppLogger.ui.info(
            "friend accept begin",
            context: [
                "friend_id": requestID.uuidString,
                "has_local_request": originalRequest != nil,
                "incoming": incomingRequests.count,
                "outgoing": outgoingRequests.count,
                "friends": friends.count
            ]
        )

        advanceStateVersion()
        removePendingRequest(id: requestID)
        if let originalRequest {
            upsertAcceptedFriend(originalRequest.withStatus("accepted"))
        }

        do {
            let accepted = try await service.acceptRequest(friendID: requestID)
            advanceStateVersion()
            upsertAcceptedFriend(accepted)
            AppLogger.ui.info(
                "friend accept success",
                context: [
                    "friend_id": requestID.uuidString,
                    "friends": friends.count
                ]
            )
            Task { await load(service: service, force: true) }
        } catch {
            if await reconcileAcceptedState(
                service: service,
                requestID: requestID,
                originalRequest: originalRequest,
                error: error
            ) {
                return
            }

            AppLogger.ui.error(
                "friend accept failed",
                error: error,
                context: ["friend_id": requestID.uuidString]
            )
            advanceStateVersion()
            rollbackAcceptedFriend(id: requestID, originalRequest: originalRequest)
            self.error = "Failed to accept friend request"
        }
    }

    func rejectRequest(service: FriendAPIService, requestID: UUID) async {
        guard rejectingRequestIDs.insert(requestID).inserted else { return }
        defer { rejectingRequestIDs.remove(requestID) }

        let originalRequest = incomingRequests.first(where: { $0.id == requestID })
        AppLogger.ui.info(
            "friend reject begin",
            context: ["friend_id": requestID.uuidString]
        )

        advanceStateVersion()
        removePendingRequest(id: requestID)
        do {
            try await service.rejectRequest(friendID: requestID)
            AppLogger.ui.info(
                "friend reject success",
                context: ["friend_id": requestID.uuidString]
            )
            Task { await load(service: service, force: true) }
        } catch {
            let reconciled = await reconcilePendingRemoval(
                service: service,
                requestID: requestID,
                direction: "incoming",
                error: error
            )
            if !reconciled {
                advanceStateVersion()
                restoreIncomingRequest(originalRequest)
            }
            AppLogger.ui.error(
                "friend reject failed",
                error: error,
                context: ["friend_id": requestID.uuidString]
            )
            self.error = "Failed to reject friend request"
        }
    }

    /// Cancel an outgoing friend request. Uses the same reject endpoint on the
    /// server (which deletes pending rows regardless of direction once it matches).
    func cancelOutgoingRequest(service: FriendAPIService, targetID: UUID) async {
        guard cancellingRequestIDs.insert(targetID).inserted else { return }
        defer { cancellingRequestIDs.remove(targetID) }

        let originalRequest = outgoingRequests.first(where: { $0.id == targetID })
        AppLogger.ui.info(
            "friend cancel begin",
            context: ["friend_id": targetID.uuidString]
        )

        advanceStateVersion()
        removePendingRequest(id: targetID)
        do {
            try await service.rejectRequest(friendID: targetID)
            AppLogger.ui.info(
                "friend cancel success",
                context: ["friend_id": targetID.uuidString]
            )
            Task { await load(service: service, force: true) }
        } catch {
            let reconciled = await reconcilePendingRemoval(
                service: service,
                requestID: targetID,
                direction: "outgoing",
                error: error
            )
            if !reconciled {
                advanceStateVersion()
                restoreOutgoingRequest(originalRequest)
            }
            AppLogger.ui.error(
                "friend cancel failed",
                error: error,
                context: ["friend_id": targetID.uuidString]
            )
            self.error = "Failed to cancel request"
        }
    }

    func blockUser(id: UUID, user: UserAPIService, friends friendsService: FriendAPIService) async {
        advanceStateVersion()
        self.friends.removeAll { $0.id == id }
        removePendingRequest(id: id)
        do {
            try await user.blockUser(id: id)
            await load(service: friendsService, force: true)
        } catch {
            AppLogger.ui.error(
                "friend block failed",
                error: error,
                context: ["friend_id": id.uuidString]
            )
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
        let overlappingIncomingCount = incomingList.lazy.filter { acceptedIDs.contains($0.id) }.count
        let overlappingOutgoingCount = outgoingList.lazy.filter { acceptedIDs.contains($0.id) }.count

        if overlappingIncomingCount > 0 || overlappingOutgoingCount > 0 {
            AppLogger.ui.warning(
                "friends snapshot contained pending rows for accepted friends",
                context: [
                    "friends": acceptedFriends.count,
                    "incoming_overlap": overlappingIncomingCount,
                    "outgoing_overlap": overlappingOutgoingCount
                ]
            )
        }

        friends = acceptedFriends
        incomingRequests = uniquedByID(incomingList)
            .filter { !acceptedIDs.contains($0.id) }
        outgoingRequests = uniquedByID(outgoingList)
            .filter { !acceptedIDs.contains($0.id) }
    }

    private func upsertAcceptedFriend(_ friend: FriendResponse) {
        let accepted = friend.withStatus("accepted")
        removePendingRequest(id: accepted.id)
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

    private func advanceStateVersion() {
        stateVersion += 1
    }

    private func removePendingRequest(id: UUID) {
        incomingRequests.removeAll { $0.id == id }
        outgoingRequests.removeAll { $0.id == id }
    }

    private func restoreIncomingRequest(_ request: FriendResponse?) {
        guard let request,
              !incomingRequests.contains(where: { $0.id == request.id }) else { return }
        incomingRequests.insert(request, at: 0)
    }

    private func restoreOutgoingRequest(_ request: FriendResponse?) {
        guard let request,
              !outgoingRequests.contains(where: { $0.id == request.id }) else { return }
        outgoingRequests.insert(request, at: 0)
    }

    private func rollbackAcceptedFriend(id: UUID, originalRequest: FriendResponse?) {
        friends.removeAll { $0.id == id }
        restoreIncomingRequest(originalRequest)
    }

    private func reconcileAcceptedState(
        service: FriendAPIService,
        requestID: UUID,
        originalRequest: FriendResponse?,
        error: Error
    ) async -> Bool {
        let message = isNotPending(error)
            ? "friend accept returned not pending; reconciling"
            : "friend accept failed; reconciling with server"
        AppLogger.ui.warning(
            message,
            error: error,
            context: ["friend_id": requestID.uuidString]
        )

        let refreshed = await load(service: service, force: true)
        let isFriend = friends.contains(where: { $0.id == requestID })
        let stillPending = incomingRequests.contains(where: { $0.id == requestID })
            || outgoingRequests.contains(where: { $0.id == requestID })

        AppLogger.ui.info(
            "friend accept reconcile result",
            context: [
                "friend_id": requestID.uuidString,
                "refreshed": refreshed,
                "is_friend": isFriend,
                "still_pending": stillPending
            ]
        )

        if isFriend {
            return true
        }

        if refreshed && !stillPending {
            if let originalRequest {
                upsertAcceptedFriend(originalRequest.withStatus("accepted"))
            }
            AppLogger.ui.warning(
                "friend accept reconcile removed pending row but friend list still missing user",
                context: ["friend_id": requestID.uuidString]
            )
            Task { await load(service: service, force: true) }
            return true
        }

        return false
    }

    private func reconcilePendingRemoval(
        service: FriendAPIService,
        requestID: UUID,
        direction: String,
        error: Error
    ) async -> Bool {
        let refreshed = await load(service: service, force: true)
        let stillPending = incomingRequests.contains(where: { $0.id == requestID })
            || outgoingRequests.contains(where: { $0.id == requestID })

        if refreshed && !stillPending {
            AppLogger.ui.warning(
                "friend pending removal reconciled after error",
                error: error,
                context: [
                    "friend_id": requestID.uuidString,
                    "direction": direction
                ]
            )
            return true
        }

        return false
    }

    private func isNotPending(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == "Vapor", nsError.code == 400 else { return false }
        return nsError.localizedDescription.localizedCaseInsensitiveContains("not pending")
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
