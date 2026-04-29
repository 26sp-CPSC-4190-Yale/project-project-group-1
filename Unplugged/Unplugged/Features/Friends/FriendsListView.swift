import Combine
import SwiftUI
import UnpluggedShared

struct FriendsListView: View {
    @Environment(DependencyContainer.self) private var deps
    @Environment(\.scenePhase) private var scenePhase
    let refreshToken: Int
    @State private var viewModel = FriendsListViewModel()
    @State private var selectedFriend: FriendResponse?
    @State private var isVisible = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .spacingSm) {
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
                                            Task {
                                                await viewModel.nudge(
                                                    service: deps.friends,
                                                    friendID: friend.id
                                                )
                                            }
                                        } label: {
                                            Label("Nudge", systemImage: "bell.badge.fill")
                                        }
                                        .disabled(viewModel.isNudging(friendID: friend.id))
                                        Button(role: .destructive) {
                                            Task {
                                                await viewModel.removeFriend(
                                                    service: deps.friends,
                                                    friend: friend
                                                )
                                            }
                                        } label: {
                                            Label("Remove Friend", systemImage: "person.badge.minus")
                                        }
                                        .disabled(viewModel.isRemovingFriend(friendID: friend.id))
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
            .task(id: refreshToken) {
                guard refreshToken > 0 else { return }
                await viewModel.load(service: deps.friends, force: true)
            }
            .task(id: shouldPoll) {
                guard shouldPoll else { return }
                // Friends state should not depend on APNs to become consistent.
                while !Task.isCancelled {
                    await viewModel.load(service: deps.friends, force: true)
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            .onAppear {
                isVisible = true
                Task { await viewModel.load(service: deps.friends, force: true) }
            }
            .onDisappear {
                isVisible = false
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                Task { await viewModel.load(service: deps.friends, force: true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .unpluggedFriendsDidChange)) { _ in
                Task { await viewModel.load(service: deps.friends, force: true) }
            }
            .refreshable {
                await viewModel.load(service: deps.friends)
            }
            .errorAlert($viewModel.error)
        }
    }

    private var shouldPoll: Bool {
        isVisible && scenePhase == .active
    }

    // MARK: - Rows

    private func incomingRow(request: FriendResponse) -> some View {
        let isAccepting = viewModel.isAccepting(requestID: request.id)
        let isRejecting = viewModel.isRejecting(requestID: request.id)
        let isBusy = isAccepting || isRejecting

        return HStack(spacing: .spacingMd) {
            ParticipantAvatar(name: request.username, size: 40)
            Text(request.username)
                .font(.body)
                .foregroundStyle(Color.tertiaryColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: .spacingSm)
            HStack(spacing: .spacingSm) {
                Button {
                    Task { await viewModel.acceptRequest(service: deps.friends, requestID: request.id) }
                } label: {
                    acceptButtonLabel(isLoading: isAccepting)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                Button {
                    Task { await viewModel.rejectRequest(service: deps.friends, requestID: request.id) }
                } label: {
                    rejectButtonLabel(isLoading: isRejecting)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.spacingMd)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func outgoingRow(request: FriendResponse) -> some View {
        let isCancelling = viewModel.isCancelling(requestID: request.id)

        return HStack(spacing: .spacingMd) {
            ParticipantAvatar(name: request.username, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.username)
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Request sent")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.5))
            }
            Spacer(minLength: .spacingSm)
            Button {
                Task {
                    await viewModel.cancelOutgoingRequest(
                        service: deps.friends,
                        targetID: request.id
                    )
                }
            } label: {
                cancelButtonLabel(isLoading: isCancelling)
            }
            .buttonStyle(.plain)
            .disabled(isCancelling)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.spacingMd)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func acceptButtonLabel(isLoading: Bool) -> some View {
        ZStack {
            Text("Accept")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primaryColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(isLoading ? 0 : 1)

            ProgressView()
                .controlSize(.small)
                .tint(.primaryColor)
                .opacity(isLoading ? 1 : 0)
        }
        .frame(minWidth: 54, minHeight: 20)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.tertiaryColor)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .animation(.easeInOut(duration: 0.15), value: isLoading)
        .accessibilityLabel(isLoading ? "Accepting" : "Accept")
    }

    private func rejectButtonLabel(isLoading: Bool) -> some View {
        ZStack {
            Image(systemName: "xmark")
                .font(.subheadline)
                .foregroundStyle(Color.tertiaryColor.opacity(0.5))
                .opacity(isLoading ? 0 : 1)

            ProgressView()
                .controlSize(.small)
                .tint(.tertiaryColor)
                .opacity(isLoading ? 1 : 0)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isLoading)
        .accessibilityLabel(isLoading ? "Rejecting" : "Reject")
    }

    private func cancelButtonLabel(isLoading: Bool) -> some View {
        ZStack {
            Text("Cancel")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.tertiaryColor.opacity(0.8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(isLoading ? 0 : 1)

            ProgressView()
                .controlSize(.small)
                .tint(.tertiaryColor)
                .opacity(isLoading ? 1 : 0)
        }
        .frame(minWidth: 54, minHeight: 20)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .strokeBorder(Color.tertiaryColor.opacity(0.3), lineWidth: 1)
        )
        .contentShape(Capsule())
        .animation(.easeInOut(duration: 0.15), value: isLoading)
        .accessibilityLabel(isLoading ? "Cancelling" : "Cancel")
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
    FriendsListView(refreshToken: 0)
        .environment(DependencyContainer())
}
