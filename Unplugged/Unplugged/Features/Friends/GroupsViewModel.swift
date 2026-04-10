//
//  GroupsViewModel.swift
//  Unplugged.Features.Friends
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class GroupsViewModel {
    var groups: [GroupResponse] = []
    var isLoading = false
    var error: String?

    var showCreate = false
    var newGroupName = ""

    func load(service: GroupAPIService) async {
        isLoading = true
        error = nil
        do {
            groups = try await service.listGroups()
        } catch {
            self.error = "Could not load groups"
        }
        isLoading = false
    }

    func createGroup(service: GroupAPIService) async {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let created = try await service.createGroup(name: trimmed)
            groups.append(created)
            newGroupName = ""
            showCreate = false
        } catch {
            self.error = "Could not create group"
        }
    }

    func deleteGroup(_ group: GroupResponse, service: GroupAPIService) async {
        do {
            try await service.deleteGroup(id: group.id)
            groups.removeAll { $0.id == group.id }
        } catch {
            self.error = "Could not delete group"
        }
    }

    func addMember(to group: GroupResponse, userID: UUID, service: GroupAPIService) async {
        do {
            let updated = try await service.addMember(groupID: group.id, userID: userID)
            if let idx = groups.firstIndex(where: { $0.id == updated.id }) {
                groups[idx] = updated
            }
        } catch {
            self.error = "Could not add member"
        }
    }
}
