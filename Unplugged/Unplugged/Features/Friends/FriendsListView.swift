import SwiftUI
import UnpluggedShared

struct FriendsListView: View {
    @Environment(DependencyContainer.self) private var deps
    @Environment(\.scenePhase) private var scenePhase
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

                        if !viewModel.visibleIncomingRequests.isEmpty {
                            Section {
                                ForEach(viewModel.visibleIncomingRequests) { request in
                                    incomingRow(request: request)
                                }
                            } header: {
                                sectionHeader("Friend Requests")
                            }
                            .padding(.bottom, .spacingMd)
                        }

                        if !viewModel.visibleOutgoingRequests.isEmpty {
                            Section {
                                ForEach(viewModel.visibleOutgoingRequests) { request in
                                    outgoingRow(request: request)
                                }
                            } header: {
                                sectionHeader("Pending")
                            }
                            .padding(.bottom, .spacingMd)
                        }

                        // Friends Section
                        if !viewModel.visibleFriends.isEmpty {
                            Section {
                                ForEach(viewModel.filteredFriends) { friend in
                                    Button {
                                        selectedFriend = friend
                                    } label: {
                                        friendRow(friend: friend)
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
                                sectionHeader("My Friends")
                            }
                        }

                        if viewModel.isLoading && viewModel.visibleFriends.isEmpty {
                            ProgressView()
                                .tint(.tertiaryColor)
                                .padding(.top, 60)
                        } else if viewModel.visibleFriends.isEmpty
                                    && viewModel.visibleIncomingRequests.isEmpty
                                    && viewModel.visibleOutgoingRequests.isEmpty {
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
                FriendProfileView(friend: friend)
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
                AddFriendSheet(existingFriendIDs: viewModel.excludedAddFriendIDs) { username in
                    viewModel.addFriendUsername = username
                    return await viewModel.addFriend(service: deps.friends)
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
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                Task { await viewModel.load(service: deps.friends, force: true) }
            }
            .refreshable {
                await viewModel.load(service: deps.friends)
            }
            .errorAlert($viewModel.error)
        }
    }

    // MARK: - Rows

    private func incomingRow(request: FriendResponse) -> some View {
        HStack(spacing: .spacingMd) {
            ParticipantAvatar(name: request.username, size: 40)
            Text(request.username)
                .font(.body)
                .foregroundStyle(Color.tertiaryColor)
            Spacer()
            Button {
                Task { await viewModel.acceptRequest(service: deps.friends, requestID: request.id) }
            } label: {
                Group {
                    if viewModel.isAccepting(requestID: request.id) {
                        ProgressView()
                            .tint(.primaryColor)
                            .frame(width: 44, height: 20)
                    } else {
                        Text("Accept")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primaryColor)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.tertiaryColor)
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(
                viewModel.isAccepting(requestID: request.id)
                    || viewModel.isRejecting(requestID: request.id)
            )
            Button {
                Task { await viewModel.rejectRequest(service: deps.friends, requestID: request.id) }
            } label: {
                Group {
                    if viewModel.isRejecting(requestID: request.id) {
                        ProgressView()
                            .tint(.tertiaryColor)
                    } else {
                        Image(systemName: "xmark")
                            .font(.subheadline)
                            .foregroundStyle(Color.tertiaryColor.opacity(0.5))
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(
                viewModel.isAccepting(requestID: request.id)
                    || viewModel.isRejecting(requestID: request.id)
            )
        }
        .padding(.spacingMd)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func outgoingRow(request: FriendResponse) -> some View {
        HStack(spacing: .spacingMd) {
            ParticipantAvatar(name: request.username, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.username)
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor)
                Text("Request sent")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.5))
            }
            Spacer()
            Button {
                Task {
                    await viewModel.cancelOutgoingRequest(
                        service: deps.friends,
                        targetID: request.id
                    )
                }
            } label: {
                Group {
                    if viewModel.isCancelling(requestID: request.id) {
                        ProgressView()
                            .tint(.tertiaryColor)
                            .frame(width: 44, height: 20)
                    } else {
                        Text("Cancel")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.tertiaryColor.opacity(0.8))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .strokeBorder(Color.tertiaryColor.opacity(0.3), lineWidth: 1)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isCancelling(requestID: request.id))
        }
        .padding(.spacingMd)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func friendRow(friend: FriendResponse) -> some View {
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.tertiaryColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, .spacingSm)
            .padding(.bottom, 4)
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

#Preview {
    FriendsListView()
        .environment(DependencyContainer())
}
