//
//  ScreenTimePermissionView.swift
//  Unplugged.Features.Onboarding
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

struct ScreenTimePermissionView: View {
    let screenTime: ScreenTimeService
    var onDone: () -> Void

    @State private var viewModel = ScreenTimePermissionViewModel()

    var body: some View {
        VStack(spacing: .spacingLg) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.tertiaryColor)

            VStack(spacing: .spacingMd) {
                Text("Emergency Apps")
                    .font(.title2.bold())
                    .foregroundStyle(Color.tertiaryColor)

                Text("Pick the apps that should stay available during a session — Phone, Messages, Maps, anything you need in an emergency.")
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            if !screenTime.isAvailable {
                Text("Screen Time is unavailable on this device, so there's nothing to pick here. You can continue.")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                    .multilineTextAlignment(.center)
            } else {
                Button {
                    Task {
                        await viewModel.beginEditingSelection(service: screenTime)
                    }
                } label: {
                    Group {
                        if viewModel.isLoadingSelection {
                            ProgressView()
                                .tint(Color.primaryColor)
                        } else {
                            Text(viewModel.didConfirm ? "Edit Emergency Apps" : "Pick Emergency Apps")
                        }
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.tertiaryColor)
                    .foregroundStyle(Color.primaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoadingSelection)

                if viewModel.didConfirm {
                    EmergencySelectionSummary(viewModel: viewModel)
                }
            }
        }
        .task {
            await viewModel.loadSavedSelection(service: screenTime)
        }
        .errorAlert($viewModel.selectionError)
        #if canImport(FamilyControls)
        .sheet(isPresented: $viewModel.showPicker) {
            EmergencySelectionSheet(
                viewModel: viewModel,
                onCancel: {
                    viewModel.resetDraftToSavedSelection()
                    viewModel.showPicker = false
                },
                onSave: {
                    Task {
                        let didSave = await viewModel.confirmSelection(service: screenTime)
                        if didSave {
                            viewModel.showPicker = false
                            onDone()
                        }
                    }
                }
            )
        }
        #endif
    }
}

#if canImport(FamilyControls)
private struct EmergencySelectionSummary: View {
    @Bindable var viewModel: ScreenTimePermissionViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingSm) {
            Label("Emergency apps saved", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.tertiaryColor)

            if viewModel.hasSavedEmergencySelection {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(viewModel.savedSystemApplications) { application in
                        systemApplicationChip(application)
                    }

                    ForEach(Array(viewModel.savedSelection.applicationTokens), id: \.self) { token in
                        familyActivityChip {
                            Label(token)
                        }
                    }

                    ForEach(Array(viewModel.savedSelection.categoryTokens), id: \.self) { token in
                        familyActivityChip {
                            Label(token)
                        }
                    }

                    ForEach(Array(viewModel.savedSelection.webDomainTokens), id: \.self) { token in
                        familyActivityChip {
                            Label(token)
                        }
                    }
                }
            } else {
                Label("No emergency apps selected", systemImage: "minus.circle")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.spacingMd)
        .background(Color.tertiaryColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func systemApplicationChip(_ application: EmergencySystemApplication) -> some View {
        HStack(spacing: 6) {
            Image(systemName: application.symbolName)
                .frame(width: 18)
            Text(application.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.tertiaryColor)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tertiaryColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func familyActivityChip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.tertiaryColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tertiaryColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmergencySelectionSheet: View {
    @Bindable var viewModel: ScreenTimePermissionViewModel
    var onCancel: () -> Void
    var onSave: () -> Void
    @State private var mode: Mode = .appleApps

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 10)
    ]

    private enum Mode: String, CaseIterable, Identifiable {
        case appleApps = "Apple Apps"
        case otherApps = "Other Apps"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, .spacingLg)
                .padding(.top, .spacingMd)

                Group {
                    switch mode {
                    case .appleApps:
                        ScrollView {
                            appleAppsContent
                                .padding(.spacingLg)
                        }
                    case .otherApps:
                        FamilyActivityPicker(selection: $viewModel.selection)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, .spacingMd)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.primaryColor.ignoresSafeArea())
            .navigationTitle("Emergency Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(viewModel.isSavingSelection)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onSave) {
                        if viewModel.isSavingSelection {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(viewModel.isSavingSelection)
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private var appleAppsContent: some View {
        VStack(alignment: .leading, spacing: .spacingLg) {
            VStack(alignment: .leading, spacing: .spacingMd) {
                Text("Apple Apps")
                    .font(.headline)
                    .foregroundStyle(Color.tertiaryColor)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(EmergencySystemApplication.allCases) { application in
                        systemApplicationButton(application)
                    }
                }
            }

            VStack(alignment: .leading, spacing: .spacingMd) {
                Text("Other Apps and Websites")
                    .font(.headline)
                    .foregroundStyle(Color.tertiaryColor)

                Button {
                    mode = .otherApps
                } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                        Text("Open App Picker")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primaryColor)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(Color.tertiaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func systemApplicationButton(_ application: EmergencySystemApplication) -> some View {
        let isAllowed = viewModel.isSystemApplicationAllowed(application)

        return Button {
            viewModel.toggleSystemApplication(application)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: application.symbolName)
                    .frame(width: 22)
                Text(application.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: isAllowed ? "checkmark.circle.fill" : "circle")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isAllowed ? Color.primaryColor : Color.tertiaryColor)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(isAllowed ? Color.tertiaryColor : Color.tertiaryColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
#endif
