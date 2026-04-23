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
private struct EmergencyTileLabelStyle: LabelStyle {
    var iconSize: CGFloat = 22
    var spacing: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
                .font(.system(size: iconSize))
                .frame(width: iconSize, height: iconSize)
            configuration.title
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private extension View {
    func emergencyActivityLabelStyle(
        foreground: Color,
        colorScheme: ColorScheme,
        iconSize: CGFloat = 22,
        spacing: CGFloat = 8,
        font: Font = .subheadline.weight(.medium)
    ) -> some View {
        return self
            .labelStyle(EmergencyTileLabelStyle(iconSize: iconSize, spacing: spacing))
            .font(font)
            .foregroundStyle(foreground)
            .tint(foreground)
            .environment(\.colorScheme, colorScheme)
    }
}

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
                        summaryChip {
                            Label(application.title, systemImage: application.symbolName)
                        }
                    }

                    ForEach(Array(viewModel.savedSelection.applicationTokens), id: \.self) { token in
                        summaryChip {
                            Label(token)
                        }
                    }

                    ForEach(Array(viewModel.savedSelection.categoryTokens), id: \.self) { token in
                        summaryChip {
                            Label(token)
                        }
                    }

                    ForEach(Array(viewModel.savedSelection.webDomainTokens), id: \.self) { token in
                        summaryChip {
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

    private func summaryChip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        return content()
            .emergencyActivityLabelStyle(
                foreground: Color.tertiaryColor,
                colorScheme: .dark,
                iconSize: 18,
                spacing: 6,
                font: .caption.weight(.semibold)
            )
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
    @State private var showingFamilyPicker = false

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: .spacingMd) {
                    Text("Pick what stays available during a session. Tap a tile to toggle it.")
                        .font(.footnote)
                        .foregroundStyle(Color.tertiaryColor.opacity(0.7))

                    LazyVGrid(columns: columns, spacing: 10) {
                        addMoreTile

                        ForEach(EmergencySystemApplication.allCases) { application in
                            emergencyTile(
                                isSelected: viewModel.isSystemApplicationAllowed(application),
                                action: { viewModel.toggleSystemApplication(application) }
                            ) {
                                Label(application.title, systemImage: application.symbolName)
                            }
                        }

                        ForEach(Array(viewModel.selection.applicationTokens), id: \.self) { token in
                            emergencyTile(
                                isSelected: true,
                                action: { viewModel.selection.applicationTokens.remove(token) }
                            ) {
                                Label(token)
                            }
                        }

                        ForEach(Array(viewModel.selection.categoryTokens), id: \.self) { token in
                            emergencyTile(
                                isSelected: true,
                                action: { viewModel.selection.categoryTokens.remove(token) }
                            ) {
                                Label(token)
                            }
                        }

                        ForEach(Array(viewModel.selection.webDomainTokens), id: \.self) { token in
                            emergencyTile(
                                isSelected: true,
                                action: { viewModel.selection.webDomainTokens.remove(token) }
                            ) {
                                Label(token)
                            }
                        }
                    }
                }
                .padding(.spacingLg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showingFamilyPicker) {
                NavigationStack {
                    FamilyActivityPicker(selection: $viewModel.selection)
                        .navigationTitle("Other Apps & Websites")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingFamilyPicker = false }
                                    .fontWeight(.semibold)
                            }
                        }
                }
                .preferredColorScheme(.dark)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .tint(Color.primaryColor)
            }
        }
    }

    private var addMoreTile: some View {
        return Button {
            showingFamilyPicker = true
        } label: {
            Label("Add More", systemImage: "plus.circle.fill")
                .emergencyActivityLabelStyle(
                    foreground: Color.tertiaryColor,
                    colorScheme: .dark,
                    font: .subheadline.weight(.semibold)
                )
                .padding(.horizontal, 12)
                .frame(height: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.tertiaryColor.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func emergencyTile<Content: View>(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Content
    ) -> some View {
        let foreground = isSelected ? Color.primaryColor : Color.tertiaryColor
        let contentColorScheme: ColorScheme = isSelected ? .light : .dark

        return Button(action: action) {
            HStack(spacing: 8) {
                label()
                    .emergencyActivityLabelStyle(
                        foreground: foreground,
                        colorScheme: contentColorScheme
                    )
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.tertiaryColor : Color.tertiaryColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
#endif
