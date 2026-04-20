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
                    LazyVStack(spacing: .spacingSm) {
                        // Incoming Requests Section
                        if !viewModel.incomingRequests.isEmpty {
                            Section {
                                ForEach(viewModel.incomingRequests) { request in
                                    HStack(spacing: .spacingMd) {
                                        ParticipantAvatar(name: request.username, size: 40)
                                        Text(request.username)
                                            .font(.body)
                                            .foregroundStyle(Color.tertiaryColor)
                                        Spacer()
                                        Button {
                                            Task { await viewModel.acceptRequest(service: deps.friends, requestID: request.id) }
                                        } label: {
                                            Text("Accept")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.primaryColor)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Color.tertiaryColor)
                                                .clipShape(Capsule())
                                        }
                                        Button {
                                            Task { await viewModel.rejectRequest(service: deps.friends, requestID: request.id) }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.subheadline)
                                                .foregroundStyle(Color.tertiaryColor.opacity(0.5))
                                                .padding(8)
                                        }
                                    }
                                    .padding(.spacingMd)
                                    .background(Color.surfaceColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            } header: {
                                Text("Friend Requests")
                                    .font(.headline)
                                    .foregroundStyle(Color.tertiaryColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, .spacingSm)
                                    .padding(.bottom, 4)
                            }
                            .padding(.bottom, .spacingMd)
                        }

                        // Friends Section
                        if !viewModel.friends.isEmpty {
                            Section {
                                ForEach(viewModel.filteredFriends) { friend in
                                    NavigationLink {
                                        FriendDetailView(friend: friend)
                                    } label: {
                                        HStack(spacing: .spacingMd) {
                                            ParticipantAvatar(name: friend.username, size: 44)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(friend.username)
                                                    .font(.body)
                                                    .foregroundStyle(Color.tertiaryColor)
                                                Text(statusLabel(for: friend))
                                                    .font(.caption)
                                                    .foregroundStyle(statusColor(for: friend))
                                            }

                                            Spacer()

                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(Color.tertiaryColor.opacity(0.3))
                                        }
                                        .padding(.spacingMd)
                                        .background(Color.surfaceColor)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            } header: {
                                Text("My Friends")
                                    .font(.headline)
                                    .foregroundStyle(Color.tertiaryColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if viewModel.friends.isEmpty && !viewModel.isLoading {
                            VStack(spacing: .spacingMd) {
                                Image(systemName: "person.2")
                                    .font(.system(size: 48))
                                    .foregroundStyle(Color.tertiaryColor.opacity(0.3))
                                Text("No friends yet")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.tertiaryColor.opacity(0.5))
                                Text("Tap + to add a friend by username")
                                    .font(.caption)
                                    .foregroundStyle(Color.tertiaryColor.opacity(0.3))
                            }
                            .padding(.top, 60)
                        }
                    }
                    .padding(.horizontal, .spacingLg)
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $viewModel.searchText, prompt: "Search friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { viewModel.showAddFriend = true } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(Color.tertiaryColor)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAddFriend) {
                AddFriendSheet { username in
                    viewModel.addFriendUsername = username
                    await viewModel.addFriend(service: deps.friends)
                }
            }
            .task {
                await viewModel.load(service: deps.friends)
            }
            .refreshable {
                await viewModel.load(service: deps.friends)
            }
            .errorAlert($viewModel.error)
        }
    }

    private func statusLabel(for friend: FriendResponse) -> String {
        switch friend.presence {
        case .unplugged: return "Currently unplugged"
        case .online:    return "Online"
        case .offline:
            if let last = friend.lastActiveAt {
                return "Seen \(last.toRelativeTime())"
            }
            return "Offline"
        }
    }

    private func statusColor(for friend: FriendResponse) -> Color {
        switch friend.presence {
        case .unplugged: return .green
        case .online:    return .tertiaryColor.opacity(0.6)
        case .offline:   return .tertiaryColor.opacity(0.4)
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
                    .font(.title.bold())
                    .foregroundStyle(Color.tertiaryColor)

                // Presence badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(presenceColor(for: friend.presence))
                        .frame(width: 8, height: 8)
                    Text(presenceLabel(for: friend.presence))
                        .font(.subheadline)
                        .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                }

                StatBadge(value: "\(friend.hoursUnplugged)", label: "Hours Focused", valueSize: 28)
                    .padding(.horizontal, .spacingLg)

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func presenceLabel(for presence: PresenceStatus) -> String {
        switch presence {
        case .online:    return "Online"
        case .unplugged: return "Currently unplugged"
        case .offline:   return "Offline"
        }
    }

    private func presenceColor(for presence: PresenceStatus) -> Color {
        switch presence {
        case .online:    return .green
        case .unplugged: return .orange
        case .offline:   return .gray
        }
    }
}

#Preview {
    FriendsListView()
        .environment(DependencyContainer())
}
