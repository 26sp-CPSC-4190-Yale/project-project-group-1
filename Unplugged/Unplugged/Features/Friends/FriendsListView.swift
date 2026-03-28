//
//  FriendsListView.swift
//  Unplugged.Features.Friends
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct FriendsListView: View {
    @State private var viewModel = FriendsListViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .spacingSm) {
                        ForEach(viewModel.filteredFriends) { friend in
                            NavigationLink {
                                FriendDetailView(friend: friend)
                            } label: {
                                HStack(spacing: .spacingMd) {
                                    ParticipantAvatar(name: friend.name, size: 48)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.name)
                                            .font(.bodyFont)
                                            .foregroundColor(.tertiaryColor)
                                        Text(friend.status)
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
                TextField("Username", text: .constant(""))
                Button("Cancel", role: .cancel) {}
                Button("Add") {}
            } message: {
                Text("Enter your friend's username")
            }
        }
    }
}

struct FriendDetailView: View {
    let friend: MockFriend

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            VStack(spacing: .spacingLg) {
                ParticipantAvatar(name: friend.name, size: 80)
                    .padding(.top, .spacingXl)

                Text(friend.name)
                    .font(.titleFont)
                    .foregroundColor(.tertiaryColor)

                Text(friend.username)
                    .font(.bodyFont)
                    .foregroundColor(.tertiaryColor.opacity(0.6))

                StatBadge(value: "\(friend.hoursUnplugged)", label: "Hours Focused", valueSize: 28)
                    .padding(.horizontal, .spacingLg)

                Text(friend.status)
                    .font(.bodyFont)
                    .foregroundColor(.tertiaryColor.opacity(0.7))

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    FriendsListView()
}
