//
//  MedalsGalleryView.swift
//  Unplugged.Features.Profile
//
//  Gallery of all medals in the catalog. Unlocked medals appear first;
//  locked medals are grayed out. Tap any medal to see the detail sheet.
//

import SwiftUI
import UnpluggedShared

@MainActor
@Observable
final class MedalsGalleryViewModel {
    var entries: [MedalCatalogEntry] = []
    var isLoading = false
    var error: String?
    var selected: MedalCatalogEntry?

    func load(service: MedalsAPIService) async {
        isLoading = true
        error = nil
        do {
            entries = try await service.getCatalog()
        } catch is CancellationError {
            // View torn down — not a user-facing error.
        } catch {
            self.error = "Could not load medals"
        }
        isLoading = false
    }

    var unlockedCount: Int { entries.filter { $0.isUnlocked }.count }
}

struct MedalsGalleryView: View {
    @Environment(DependencyContainer.self) private var deps
    @State private var viewModel = MedalsGalleryViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: .spacingMd)
    ]

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: .spacingLg) {
                    header

                    if viewModel.entries.isEmpty && viewModel.isLoading {
                        ProgressView()
                            .tint(.tertiaryColor)
                            .padding(.top, 60)
                    } else if viewModel.entries.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: .spacingMd) {
                            ForEach(viewModel.entries) { entry in
                                Button { viewModel.selected = entry } label: {
                                    MedalGalleryCell(entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, .spacingLg)
                    }
                }
                .padding(.top, .spacingSm)
                .padding(.bottom, .spacingLg)
            }
        }
        .navigationTitle("Medals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $viewModel.selected) { entry in
            MedalDetailSheet(entry: entry)
        }
        .task {
            await viewModel.load(service: deps.medals)
        }
        .refreshable {
            await viewModel.load(service: deps.medals)
        }
    }

    private var header: some View {
        HStack(spacing: .spacingMd) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.unlockedCount) of \(viewModel.entries.count)")
                    .font(.title2.bold())
                    .foregroundStyle(Color.tertiaryColor)
                Text("medals unlocked")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, .spacingLg)
    }

    private var emptyState: some View {
        VStack(spacing: .spacingSm) {
            Image(systemName: "trophy")
                .font(.system(size: 48))
                .foregroundStyle(Color.tertiaryColor.opacity(0.3))
            Text(viewModel.error ?? "No medals available")
                .font(.subheadline)
                .foregroundStyle(Color.tertiaryColor.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

private struct MedalGalleryCell: View {
    let entry: MedalCatalogEntry

    var body: some View {
        VStack(spacing: .spacingSm) {
            ZStack {
                Circle()
                    .fill(Color.surfaceColor)
                    .frame(width: 72, height: 72)
                Text(entry.medal.icon)
                    .font(.system(size: 40))
                    .grayscale(entry.isUnlocked ? 0 : 1)
                    .opacity(entry.isUnlocked ? 1 : 0.35)
                if !entry.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.tertiaryColor)
                        .padding(6)
                        .background(Color.primaryColor)
                        .clipShape(Circle())
                        .offset(x: 24, y: 24)
                }
            }
            Text(entry.medal.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.tertiaryColor.opacity(entry.isUnlocked ? 1 : 0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 96)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacingMd)
        .background(Color.surfaceColor.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadius))
    }
}

struct MedalDetailSheet: View {
    let entry: MedalCatalogEntry
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .spacingLg) {
                        ZStack {
                            Circle()
                                .fill(Color.surfaceColor)
                                .frame(width: 120, height: 120)
                            Text(entry.medal.icon)
                                .font(.system(size: 64))
                                .grayscale(entry.isUnlocked ? 0 : 1)
                                .opacity(entry.isUnlocked ? 1 : 0.35)
                        }
                        .padding(.top, .spacingLg)

                        Text(entry.medal.name)
                            .font(.title.bold())
                            .foregroundStyle(Color.tertiaryColor)
                            .multilineTextAlignment(.center)

                        statusPill

                        VStack(spacing: .spacingMd) {
                            infoCard(
                                icon: "info.circle.fill",
                                title: "About",
                                body: entry.medal.description
                            )

                            infoCard(
                                icon: "target",
                                title: "How to unlock",
                                body: entry.howToUnlock
                            )

                            if let earnedAt = entry.earnedAt {
                                infoCard(
                                    icon: "calendar",
                                    title: "Unlocked",
                                    body: Self.dateFormatter.string(from: earnedAt)
                                )
                            }
                        }
                        .padding(.horizontal, .spacingLg)
                    }
                    .padding(.bottom, .spacingLg)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.tertiaryColor)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.isUnlocked ? "checkmark.seal.fill" : "lock.fill")
                .font(.caption)
            Text(entry.isUnlocked ? "Unlocked" : "Locked")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(entry.isUnlocked ? Color.secondaryColor : Color.tertiaryColor.opacity(0.6))
        .padding(.horizontal, .spacingMd)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.surfaceColor)
        )
    }

    private func infoCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: .spacingMd) {
            Image(systemName: icon)
                .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(Color.tertiaryColor)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
        }
        .padding(.spacingMd)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadius))
    }
}

#Preview {
    NavigationStack {
        MedalsGalleryView()
            .environment(DependencyContainer())
    }
}
