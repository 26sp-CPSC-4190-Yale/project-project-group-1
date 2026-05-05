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
    var showPicker = false
    var didConfirm = false
    var isLoadingSelection = false
    var isSavingSelection = false
    var selectionError: String?

    var hasSavedEmergencySelection: Bool {
        #if canImport(FamilyControls)
        !savedSelection.isEmpty
        #else
        false
        #endif
    }

    func loadSavedSelection(service: ScreenTimeService) async {
        #if canImport(FamilyControls)
        guard !isLoadingSelection else { return }
        isLoadingSelection = true
        defer { isLoadingSelection = false }

        let snapshot = await service.loadEmergencyAllowlistSnapshot()
        savedSelection = snapshot.allowlist.selection

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
    }

    @discardableResult
    func confirmSelection(service: ScreenTimeService) async -> Bool {
        #if canImport(FamilyControls)
        guard !isSavingSelection else { return false }
        isSavingSelection = true
        defer { isSavingSelection = false }

        let allowlist = ScreenTimeEmergencyAllowlist(
            selection: selection,
            allowedSystemApplicationBundleIdentifiers: []
        )
        do {
            try await service.saveEmergencyAllowlist(allowlist)
            savedSelection = selection
            didConfirm = true
            selectionError = nil
            return true
        } catch {
            AppLogger.onboarding.error(
                "saveEmergencyAllowlist failed — user's emergency app choice not persisted",
                error: error,
                context: [
                    "app_tokens": selection.applicationTokens.count,
                    "category_tokens": selection.categoryTokens.count,
                    "web_domain_tokens": selection.webDomainTokens.count
                ]
            )
            selectionError = "Could not save emergency apps."
            return false
        }
        #else
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
