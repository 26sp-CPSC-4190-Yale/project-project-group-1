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
    @State private var selectedFriend: FriendResponse?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: .spacingSm) {
                        HStack {
                            Text("Friends")
                                .font(.largeTitle.bold())
                                .foregroundStyle(Color.tertiaryColor)
                            Spacer()
                        }
                        .padding(.horizontal, .spacingLg)
                        .padding(.top, .spacingSm)
                        .padding(.bottom, .spacingSm)

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
                                                .fixedSize(horizontal: true, vertical: false)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Color.tertiaryColor)
                                                .clipShape(Capsule())
                                                .contentShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        Button {
                                            Task { await viewModel.rejectRequest(service: deps.friends, requestID: request.id) }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.subheadline)
                                                .foregroundStyle(Color.tertiaryColor.opacity(0.5))
                                                .frame(width: 44, height: 44)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
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
                                    Button {
                                        selectedFriend = friend
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
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.spacingMd)
                                        .background(Color.surfaceColor)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .contentShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            viewModel.reportTarget = friend
                                        } label: {
                                            Label("Report", systemImage: "flag")
                                        }
                                        Button(role: .destructive) {
                                            Task {
                                                await viewModel.blockUser(
                                                    id: friend.id,
                                                    user: deps.user,
                                                    friends: deps.friends
                                                )
                                            }
                                        } label: {
                                            Label("Block", systemImage: "hand.raised")
                                        }
                                    }
                                }
                            } header: {
                                Text("My Friends")
                                    .font(.headline)
                                    .foregroundStyle(Color.tertiaryColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if viewModel.isLoading && viewModel.friends.isEmpty {
                            ProgressView()
                                .tint(.tertiaryColor)
                                .padding(.top, 60)
                        } else if viewModel.friends.isEmpty {
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $viewModel.searchText, prompt: "Search friends")
            .navigationDestination(item: $selectedFriend) { friend in
                FriendDetailView(friend: friend)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { viewModel.showAddFriend = true } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(Color.tertiaryColor)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $viewModel.showAddFriend) {
                AddFriendSheet(existingFriendIDs: Set(viewModel.friends.map(\.id))) { username in
                    viewModel.addFriendUsername = username
                    await viewModel.addFriend(service: deps.friends)
                }
            }
            .sheet(item: $viewModel.reportTarget) { target in
                ReportUserSheet(username: target.username) { reason, details in
                    await viewModel.reportUser(
                        id: target.id,
                        reason: reason,
                        details: details,
                        user: deps.user
                    )
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
