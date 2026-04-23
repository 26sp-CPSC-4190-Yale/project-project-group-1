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
    var excludedUserIDs: Set<UUID> = []

    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0

    func cancelSearch() {
        searchGeneration += 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    func search(usersService: UserAPIService) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            cancelSearch()
            users = []
            error = nil
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        let excludedUserIDs = excludedUserIDs
        searchTask?.cancel()
        isSearching = true
        error = nil
        AppLogger.ui.debug(
            "friend search queued",
            context: [
                "query": query,
                "generation": generation
            ]
        )

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }
            do {
                AppLogger.ui.debug(
                    "friend search begin",
                    context: [
                        "query": query,
                        "generation": generation
                    ]
                )
                let results = try await usersService.searchUsers(query: query)
                guard !Task.isCancelled, generation == self.searchGeneration else { return }
                self.users = results.filter { !excludedUserIDs.contains($0.id) }
                self.error = nil
                self.isSearching = false
                AppLogger.ui.info(
                    "friend search success",
                    context: [
                        "query": query,
                        "generation": generation,
                        "results": self.users.count
                    ]
                )
            } catch {
                guard !Task.isCancelled, generation == self.searchGeneration else { return }
                self.error = "Could not search users"
                self.isSearching = false
                AppLogger.ui.error(
                    "friend search failed",
                    error: error,
                    context: [
                        "query": query,
                        "generation": generation
                    ]
                )
            }
        }
    }
}

struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DependencyContainer.self) private var deps
    @State private var viewModel = AddFriendViewModel()

    var existingFriendIDs: Set<UUID> = []
    var onAddFriend: (String) async -> Bool

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
                        TextField("", text: $viewModel.searchText,
                                  prompt: Text("Search users by name").foregroundColor(.tertiaryColor.opacity(0.6)))
                            .foregroundColor(.tertiaryColor)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: viewModel.searchText) { _ in
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
                    .frame(height: 44)
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
                                            let didAdd = await onAddFriend(user.username)
                                            if !didAdd {
                                                viewModel.addingUserID = nil
                                            }
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
            .onAppear {
                viewModel.excludedUserIDs = existingFriendIDs
            }
            .onDisappear {
                viewModel.cancelSearch()
                viewModel.addingUserID = nil
            }
        }
    }
}
