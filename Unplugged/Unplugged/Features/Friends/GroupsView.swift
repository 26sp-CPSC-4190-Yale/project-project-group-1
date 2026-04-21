//
//  GroupsView.swift
//  Unplugged.Features.Friends
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI
import UnpluggedShared

struct GroupsView: View {
    @Environment(DependencyContainer.self) private var deps
    @State private var viewModel = GroupsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .spacingSm) {
                        if viewModel.groups.isEmpty && !viewModel.isLoading {
                            Text("No groups yet")
                                .font(.captionFont)
                                .foregroundColor(.tertiaryColor.opacity(0.5))
                                .padding(.top, .spacingLg)
                        }

                        ForEach(viewModel.groups) { group in
                            HStack(spacing: .spacingMd) {
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.tertiaryColor.opacity(0.6))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name)
                                        .font(.bodyFont)
                                        .foregroundColor(.tertiaryColor)
                                    Text("\(group.members.count) member\(group.members.count == 1 ? "" : "s")")
                                        .font(.captionFont)
                                        .foregroundColor(.tertiaryColor.opacity(0.6))
                                }

                                Spacer()
                            }
                            .padding(.spacingMd)
                            .background(Color.surfaceColor)
                            .cornerRadius(.cornerRadiusSm)
                        }
                    }
                    .padding(.horizontal, .spacingLg)
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { viewModel.showCreate = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(.tertiaryColor)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
            .alert("New Group", isPresented: $viewModel.showCreate) {
                TextField("Group name", text: $viewModel.newGroupName)
                Button("Cancel", role: .cancel) {
                    viewModel.newGroupName = ""
                }
                Button("Create") {
                    Task { await viewModel.createGroup(service: deps.groups) }
                }
            }
            .task {
                await viewModel.load(service: deps.groups)
            }
            .refreshable {
                await viewModel.load(service: deps.groups)
            }
        }
    }
}

#Preview {
    GroupsView()
        .environment(DependencyContainer())
}
