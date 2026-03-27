//
//  FriendsListViewModel.swift
//  Unplugged.Features.Friends
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

// TODO: Replace MockFriend array with FriendAPIService.listFriends(); wire addFriend to API

import Foundation
import Observation

struct MockFriend: Identifiable {
    let id: String
    let name: String
    let username: String
    let status: String
    let hoursUnplugged: Int
}

@MainActor
@Observable
class FriendsListViewModel {
    var friends: [MockFriend] = [
        MockFriend(id: "1", name: "Sean", username: "@sean", status: "Currently unplugged", hoursUnplugged: 12),
        MockFriend(id: "2", name: "Michael", username: "@michael", status: "Unplugged 2h ago", hoursUnplugged: 8),
        MockFriend(id: "3", name: "Alex", username: "@alex", status: "Online", hoursUnplugged: 24),
        MockFriend(id: "4", name: "Jordan", username: "@jordan", status: "Unplugged 5h ago", hoursUnplugged: 6),
        MockFriend(id: "5", name: "James", username: "@james", status: "Online", hoursUnplugged: 15),
    ]
    var searchText = ""
    var showAddFriend = false

    var filteredFriends: [MockFriend] {
        if searchText.isEmpty { return friends }
        return friends.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}
