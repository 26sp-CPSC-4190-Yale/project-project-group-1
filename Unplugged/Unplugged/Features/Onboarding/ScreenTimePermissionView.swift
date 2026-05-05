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

                Text("Pick apps, categories, and websites that should stay available during a session.")
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
        .sheet(item: $viewModel.activePicker) { mode in
            EmergencySelectionSheet(
                mode: mode,
                viewModel: viewModel,
                onCancel: {
                    viewModel.resetDraftToSavedSelection()
                    viewModel.activePicker = nil
                },
                onSave: {
                    Task {
                        let didSave = await viewModel.confirmSelection(service: screenTime)
                        if didSave {
                            viewModel.activePicker = nil
                            onDone()
                        }
                    }
                }
            )
        }
        #endif
    }
}

struct StrongBlockingSettingsView: View {
    let screenTime: ScreenTimeService

    @State private var viewModel = ScreenTimePermissionViewModel()

    var body: some View {
        VStack(spacing: .spacingLg) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.tertiaryColor)

            VStack(spacing: .spacingMd) {
                Text("Strong Blocking")
                    .font(.title2.bold())
                    .foregroundStyle(Color.tertiaryColor)

                Text("Add specific apps that category blocking misses. Emergency Apps still stay available.")
                    .font(.body)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            if !screenTime.isAvailable {
                Text("Screen Time is unavailable on this device.")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                    .multilineTextAlignment(.center)
            } else {
                Button {
                    Task {
                        await viewModel.beginEditingAlwaysBlockedSelection(service: screenTime)
                    }
                } label: {
                    Group {
                        if viewModel.isLoadingSelection {
                            ProgressView()
                                .tint(Color.tertiaryColor)
                        } else {
                            Text(viewModel.hasSavedAlwaysBlockedSelection ? "Edit Strong Blocking Apps" : "Pick Strong Blocking Apps")
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

                Text("Select apps such as Files, Compass, Watch, Clock, and Health directly. Avoid categories here; direct app selections use the stronger shield path.")
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                    .multilineTextAlignment(.center)

                if viewModel.hasSavedAlwaysBlockedSelection {
                    AlwaysBlockedSelectionSummary(viewModel: viewModel)
                }
            }
        }
        .task {
            await viewModel.loadSavedSelection(service: screenTime)
        }
        .errorAlert($viewModel.selectionError)
        #if canImport(FamilyControls)
        .sheet(item: $viewModel.activePicker) { mode in
            EmergencySelectionSheet(
                mode: mode,
                viewModel: viewModel,
                onCancel: {
                    viewModel.resetDraftToSavedSelection()
                    viewModel.activePicker = nil
                },
                onSave: {
                    Task {
                        let didSave = await viewModel.confirmSelection(service: screenTime)
                        if didSave {
                            viewModel.activePicker = nil
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
    var iconTint: Color?

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            tintedIcon(configuration.icon)
                .font(.system(size: iconSize))
                .frame(width: iconSize, height: iconSize)
            configuration.title
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private func tintedIcon<Icon: View>(_ icon: Icon) -> some View {
        if let iconTint {
            icon
                .saturation(0)
                .colorMultiply(iconTint)
        } else {
            icon
        }
    }
}

private extension View {
    func emergencyActivityLabelStyle(
        foreground: Color,
        colorScheme: ColorScheme,
        iconSize: CGFloat = 22,
        spacing: CGFloat = 8,
        font: Font = .subheadline.weight(.medium),
        tokenIconTint: Color? = nil
    ) -> some View {
        return self
            .labelStyle(EmergencyTileLabelStyle(iconSize: iconSize, spacing: spacing, iconTint: tokenIconTint))
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
                    ForEach(Array(viewModel.savedSelection.applicationTokens), id: \.self) { token in
                        summaryChip(tokenIconTint: Color.tertiaryColor) {
                            Label(token)
                        }
                    }

                    ForEach(Array(viewModel.savedSelection.categoryTokens), id: \.self) { token in
                        summaryChip(tokenIconTint: Color.tertiaryColor) {
                            Label(token)
                        }
                    }

                    ForEach(Array(viewModel.savedSelection.webDomainTokens), id: \.self) { token in
                        summaryChip(tokenIconTint: Color.tertiaryColor) {
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

    private func summaryChip<Content: View>(
        tokenIconTint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        return content()
            .emergencyActivityLabelStyle(
                foreground: Color.tertiaryColor,
                colorScheme: .dark,
                iconSize: 18,
                spacing: 6,
                font: .caption.weight(.semibold),
                tokenIconTint: tokenIconTint
            )
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tertiaryColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AlwaysBlockedSelectionSummary: View {
    @Bindable var viewModel: ScreenTimePermissionViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingSm) {
            Label("Strong blocking apps saved", systemImage: "lock.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.tertiaryColor)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(Array(viewModel.savedAlwaysBlockedSelection.applicationTokens), id: \.self) { token in
                    summaryChip(tokenIconTint: Color.tertiaryColor) {
                        Label(token)
                    }
                }

                ForEach(Array(viewModel.savedAlwaysBlockedSelection.webDomainTokens), id: \.self) { token in
                    summaryChip(tokenIconTint: Color.tertiaryColor) {
                        Label(token)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.spacingMd)
        .background(Color.tertiaryColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func summaryChip<Content: View>(
        tokenIconTint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        return content()
            .emergencyActivityLabelStyle(
                foreground: Color.tertiaryColor,
                colorScheme: .dark,
                iconSize: 18,
                spacing: 6,
                font: .caption.weight(.semibold),
                tokenIconTint: tokenIconTint
            )
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tertiaryColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmergencySelectionSheet: View {
    let mode: ScreenTimePermissionViewModel.PickerMode
    @Bindable var viewModel: ScreenTimePermissionViewModel
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        NavigationStack {
            picker
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primaryColor.ignoresSafeArea())
            .navigationTitle(mode.title)
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
        }
    }

    @ViewBuilder
    private var picker: some View {
        switch mode {
        case .emergency:
            FamilyActivityPicker(
                headerText: "Choose what stays available during a session.",
                footerText: "For strongest blocking, remove distracting apps from Settings > Screen Time > Always Allowed.",
                selection: $viewModel.selection
            )
        case .alwaysBlocked:
            FamilyActivityPicker(
                headerText: "Choose specific apps that category blocking misses.",
                footerText: "Emergency Apps still stay available. Select apps such as Files, Compass, Watch, Clock, or Health directly.",
                selection: $viewModel.alwaysBlockedSelection
            )
        }
    }
}
#endif

#if canImport(FamilyControls)
private extension ScreenTimePermissionViewModel.PickerMode {
    var title: String {
        switch self {
        case .emergency:
            "Emergency Apps"
        case .alwaysBlocked:
            "Strong Blocking Apps"
        }
    }
}
#endif
