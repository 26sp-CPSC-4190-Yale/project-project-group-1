//
//  ScreenTimePermissionViewModel.swift
//  Unplugged.Features.Onboarding
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Observation
#if canImport(FamilyControls)
import FamilyControls
#endif

@MainActor
@Observable
final class ScreenTimePermissionViewModel {
    #if canImport(FamilyControls)
    var selection = FamilyActivitySelection(includeEntireCategory: false)
    var savedSelection = FamilyActivitySelection(includeEntireCategory: false)
    #endif
    var allowedSystemApplicationBundleIdentifiers = Set<String>()
    var savedSystemApplicationBundleIdentifiers = Set<String>()
    var showPicker = false
    var didConfirm = false
    var isLoadingSelection = false
    var isSavingSelection = false
    var selectionError: String?

    var savedSystemApplications: [EmergencySystemApplication] {
        EmergencySystemApplication.allCases.filter {
            savedSystemApplicationBundleIdentifiers.contains($0.bundleIdentifier)
        }
    }

    var hasSavedEmergencySelection: Bool {
        #if canImport(FamilyControls)
        !savedSelection.isEmpty || !savedSystemApplicationBundleIdentifiers.isEmpty
        #else
        !savedSystemApplicationBundleIdentifiers.isEmpty
        #endif
    }

    func isSystemApplicationAllowed(_ application: EmergencySystemApplication) -> Bool {
        allowedSystemApplicationBundleIdentifiers.contains(application.bundleIdentifier)
    }

    func toggleSystemApplication(_ application: EmergencySystemApplication) {
        if isSystemApplicationAllowed(application) {
            allowedSystemApplicationBundleIdentifiers.remove(application.bundleIdentifier)
        } else {
            allowedSystemApplicationBundleIdentifiers.insert(application.bundleIdentifier)
        }
    }

    func loadSavedSelection(service: ScreenTimeService) async {
        #if canImport(FamilyControls)
        guard !isLoadingSelection else { return }
        isLoadingSelection = true
        defer { isLoadingSelection = false }

        let snapshot = await service.loadEmergencyAllowlistSnapshot()
        savedSelection = snapshot.allowlist.selection
        savedSystemApplicationBundleIdentifiers = snapshot.allowlist.allowedSystemApplicationBundleIdentifiers

        resetDraftToSavedSelection()
        didConfirm = snapshot.hasStoredValue
        #endif
    }

    func beginEditingSelection(service: ScreenTimeService) async {
        await loadSavedSelection(service: service)
        showPicker = true
    }

    func resetDraftToSavedSelection() {
        #if canImport(FamilyControls)
        selection = savedSelection
        #endif
        allowedSystemApplicationBundleIdentifiers = savedSystemApplicationBundleIdentifiers
    }

    @discardableResult
    func confirmSelection(service: ScreenTimeService) async -> Bool {
        #if canImport(FamilyControls)
        guard !isSavingSelection else { return false }
        isSavingSelection = true
        defer { isSavingSelection = false }

        let allowlist = ScreenTimeEmergencyAllowlist(
            selection: selection,
            allowedSystemApplicationBundleIdentifiers: allowedSystemApplicationBundleIdentifiers
        )
        do {
            try await service.saveEmergencyAllowlist(allowlist)
            savedSelection = selection
            savedSystemApplicationBundleIdentifiers = allowedSystemApplicationBundleIdentifiers
            didConfirm = true
            selectionError = nil
            return true
        } catch {
            AppLogger.onboarding.error(
                "saveEmergencyAllowlist failed — user's emergency app choice not persisted",
                error: error,
                context: [
                    "app_tokens": selection.applicationTokens.count,
                    "system_bundles": allowedSystemApplicationBundleIdentifiers.count
                ]
            )
            selectionError = "Could not save emergency apps."
            return false
        }
        #else
        savedSystemApplicationBundleIdentifiers = allowedSystemApplicationBundleIdentifiers
        didConfirm = true
        selectionError = nil
        return true
        #endif
    }
}

#if canImport(FamilyControls)
private extension FamilyActivitySelection {
    var isEmpty: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }
}
#endif
