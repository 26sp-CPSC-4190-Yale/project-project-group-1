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
            users = []
            error = nil
            return
        }

        searchTask?.cancel()
        isSearching = true

        searchTask = Task.detached { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce off main actor
                guard !Task.isCancelled else { return }

                let results = try await usersService.searchUsers(query: query)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self?.users = results
                    self?.isSearching = false
                    self?.error = nil
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self?.error = "Could not search users"
                        self?.isSearching = false
                    }
                }
            }
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
                            }
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
                                        if viewModel.addingUserID == user.id {
                                            ProgressView()
                                                .tint(.primaryColor)
                                                .frame(minWidth: 44, minHeight: 44)
                                        } else {
                                            Text("Add")
                                                .font(.captionFont)
                                                .fontWeight(.bold)
                                                .foregroundColor(.primaryColor)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Color.tertiaryColor)
                                                .cornerRadius(16)
                                                .frame(minHeight: 44)
                                                .contentShape(Rectangle())
                                        }
                                    }
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
