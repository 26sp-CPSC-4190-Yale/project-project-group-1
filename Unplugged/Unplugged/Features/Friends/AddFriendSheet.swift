//
//  AddFriendSheet.swift
//  Unplugged.Features.Friends
//
//  Created by Sebastian Gonzalez on 4/10/26.
//

import SwiftUI
import UnpluggedShared

@MainActor
@Observable
class AddFriendViewModel {
    var searchText = ""
    var users: [User] = []
    var isSearching = false
    var error: String?
    var addingUserID: UUID?

    private var searchTask: Task<Void, Never>?

    func search(usersService: UserAPIService) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchTask?.cancel()
            searchTask = nil
            users = []
            error = nil
            isSearching = false
            return
        }

        searchTask?.cancel()
        isSearching = true

        // A plain Task inherits the @MainActor context from the caller. We
        // don't need Task.detached + MainActor.run ping-pong: Task.sleep is
        // cooperatively yielding, and the network call awaits on a background
        // URLSession queue. Typing-fast on older hardware (iOS 17.6) was
        // paying the cost of spinning up a detached task per keystroke and
        // re-hopping to the main actor for every state update.
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }
            do {
                let results = try await usersService.searchUsers(query: query)
                guard !Task.isCancelled else { return }
                self.users = results
                self.error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Could not search users"
            }
            self.isSearching = false
        }
    }
}

struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DependencyContainer.self) private var deps
    @State private var viewModel = AddFriendViewModel()

    var onAddFriend: (String) async -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.tertiaryColor.opacity(0.5))
                        TextField("Search users by name", text: $viewModel.searchText)
                            .foregroundColor(.tertiaryColor)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: viewModel.searchText) { _, _ in
                                viewModel.search(usersService: deps.user)
                            }
                        if viewModel.isSearching {
                            ProgressView()
                                .tint(.tertiaryColor)
                                .scaleEffect(0.8)
                        } else if !viewModel.searchText.isEmpty {
                            Button(action: {
                                viewModel.searchText = ""
                                viewModel.users = []
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.tertiaryColor.opacity(0.5))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.surfaceColor)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    if let error = viewModel.error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.destructiveColor)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    if viewModel.users.isEmpty && viewModel.error == nil {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "person.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.tertiaryColor.opacity(0.3))
                            Text(viewModel.searchText.isEmpty ? "Search for friends to add" : "No users found")
                                .font(.bodyFont)
                                .foregroundColor(.tertiaryColor.opacity(0.5))
                        }
                        Spacer()
                    } else if !viewModel.users.isEmpty {
                        List {
                            ForEach(viewModel.users) { user in
                                HStack {
                                    ParticipantAvatar(name: user.username, size: 40)
                                    Text(user.username)
                                        .font(.bodyFont)
                                        .foregroundColor(.tertiaryColor)
                                    Spacer()
                                    Button(action: {
                                        viewModel.addingUserID = user.id
                                        Task {
                                            await onAddFriend(user.username)
                                            // Parent's addFriend() dismisses the sheet via showAddFriend = false.
                                            // Do NOT call dismiss() here to avoid double-dismiss crash.
                                        }
                                    }) {
                                        Group {
                                            if viewModel.addingUserID == user.id {
                                                ProgressView()
                                                    .tint(.primaryColor)
                                            } else {
                                                Text("Add")
                                                    .font(.captionFont)
                                                    .fontWeight(.bold)
                                            }
                                        }
                                        .foregroundColor(.primaryColor)
                                        .frame(minWidth: 64, minHeight: 44)
                                        .background(Color.tertiaryColor)
                                        .clipShape(Capsule())
                                        .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(viewModel.addingUserID != nil)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(.tertiaryColor.opacity(0.1))
                            }
                        }
                        .listStyle(.plain)
                        .padding(.top, 16)
                    }
                }
            }
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.tertiaryColor)
                }
            }
        }
    }
}
