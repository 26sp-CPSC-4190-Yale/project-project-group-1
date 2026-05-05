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
    var alwaysBlockedSelection = FamilyActivitySelection(includeEntireCategory: false)
    var savedAlwaysBlockedSelection = FamilyActivitySelection(includeEntireCategory: false)
    #endif
    var activePicker: PickerMode?
    var didConfirm = false
    var isLoadingSelection = false
    var isSavingSelection = false
    var selectionError: String?

    enum PickerMode: String, Identifiable {
        case emergency
        case alwaysBlocked

        var id: String { rawValue }
    }

    var hasSavedEmergencySelection: Bool {
        #if canImport(FamilyControls)
        !savedSelection.isEmpty
        #else
        false
        #endif
    }

    var hasSavedAlwaysBlockedSelection: Bool {
        #if canImport(FamilyControls)
        !savedAlwaysBlockedSelection.applicationTokens.isEmpty
            || !savedAlwaysBlockedSelection.webDomainTokens.isEmpty
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
        savedAlwaysBlockedSelection = snapshot.allowlist.alwaysBlockedSelection
            ?? FamilyActivitySelection(includeEntireCategory: false)

        resetDraftToSavedSelection()
        didConfirm = snapshot.hasStoredValue
        #endif
    }

    func beginEditingSelection(service: ScreenTimeService) async {
        await loadSavedSelection(service: service)
        activePicker = .emergency
    }

    func beginEditingAlwaysBlockedSelection(service: ScreenTimeService) async {
        await loadSavedSelection(service: service)
        activePicker = .alwaysBlocked
    }

    func resetDraftToSavedSelection() {
        #if canImport(FamilyControls)
        selection = savedSelection
        alwaysBlockedSelection = savedAlwaysBlockedSelection
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
            alwaysBlockedSelection: alwaysBlockedSelection,
            allowedSystemApplicationBundleIdentifiers: []
        )
        do {
            try await service.saveEmergencyAllowlist(allowlist)
            savedSelection = selection
            savedAlwaysBlockedSelection = alwaysBlockedSelection
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
                    "web_domain_tokens": selection.webDomainTokens.count,
                    "always_blocked_app_tokens": alwaysBlockedSelection.applicationTokens.count,
                    "always_blocked_web_domain_tokens": alwaysBlockedSelection.webDomainTokens.count
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
