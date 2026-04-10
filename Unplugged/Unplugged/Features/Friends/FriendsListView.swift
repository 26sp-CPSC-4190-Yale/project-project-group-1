//
//  FriendsListView.swift
//  Unplugged.Features.Friends
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI
import UnpluggedShared

struct FriendsListView: View {
    @Environment(DependencyContainer.self) private var deps
    @State private var viewModel = FriendsListViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .spacingSm) {
                        if viewModel.friends.isEmpty && !viewModel.isLoading {
                            Text("No friends yet")
                                .font(.captionFont)
                                .foregroundColor(.tertiaryColor.opacity(0.5))
                                .padding(.top, .spacingLg)
                        }

                        ForEach(viewModel.filteredFriends) { friend in
                            NavigationLink {
                                FriendDetailView(friend: friend)
                            } label: {
                                HStack(spacing: .spacingMd) {
                                    ParticipantAvatar(name: friend.username, size: 48)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.username)
                                            .font(.bodyFont)
                                            .foregroundColor(.tertiaryColor)
                                        Text(statusLabel(for: friend))
                                            .font(.captionFont)
                                            .foregroundColor(.tertiaryColor.opacity(0.6))
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.captionFont)
                                        .foregroundColor(.tertiaryColor.opacity(0.4))
                                }
                                .padding(.spacingMd)
                                .background(Color.surfaceColor)
                                .cornerRadius(.cornerRadiusSm)
                            }
                        }
                    }
                    .padding(.horizontal, .spacingLg)
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchText, prompt: "Search friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { viewModel.showAddFriend = true }) {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(.tertiaryColor)
                    }
                }
            }
            .alert("Add Friend", isPresented: $viewModel.showAddFriend) {
                TextField("Username", text: $viewModel.addFriendUsername)
                Button("Cancel", role: .cancel) {
                    viewModel.addFriendUsername = ""
                }
                Button("Add") {
                    Task { await viewModel.addFriend(service: deps.friends) }
                }
            } message: {
                Text("Enter your friend's username")
            }
            .task {
                await viewModel.load(service: deps.friends)
            }
            .refreshable {
                await viewModel.load(service: deps.friends)
            }
        }
    }

    private func statusLabel(for friend: FriendResponse) -> String {
        switch friend.presence {
        case .unplugged: return "Currently unplugged"
        case .online:    return "Online"
        case .offline:
            if let last = friend.lastActiveAt {
                return "Seen \(RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date()))"
            }
            return "Offline"
        }
    }
}

struct FriendDetailView: View {
    let friend: FriendResponse

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            VStack(spacing: .spacingLg) {
                ParticipantAvatar(name: friend.username, size: 80)
                    .padding(.top, .spacingXl)

                Text(friend.username)
                    .font(.titleFont)
                    .foregroundColor(.tertiaryColor)

                StatBadge(value: "\(friend.hoursUnplugged)", label: "Hours Focused", valueSize: 28)
                    .padding(.horizontal, .spacingLg)

                Text(presenceLabel(for: friend.presence))
                    .font(.bodyFont)
                    .foregroundColor(.tertiaryColor.opacity(0.7))

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func presenceLabel(for presence: PresenceStatus) -> String {
        switch presence {
        case .online:    return "Online"
        case .unplugged: return "Currently unplugged"
        case .offline:   return "Offline"
        }
    }
}

#Preview {
    FriendsListView()
        .environment(DependencyContainer())
}
