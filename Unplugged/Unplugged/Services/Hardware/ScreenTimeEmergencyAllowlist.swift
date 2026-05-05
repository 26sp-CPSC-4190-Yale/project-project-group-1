import Foundation
#if canImport(FamilyControls)
@preconcurrency import FamilyControls
#endif

#if canImport(FamilyControls)
nonisolated struct ScreenTimeEmergencyAllowlist: Codable, Equatable, Sendable {
    var selection: FamilyActivitySelection
    var alwaysBlockedSelection: FamilyActivitySelection?
    var allowedSystemApplicationBundleIdentifiers: Set<String>

    init(
        selection: FamilyActivitySelection = FamilyActivitySelection(includeEntireCategory: false),
        alwaysBlockedSelection: FamilyActivitySelection? = nil,
        allowedSystemApplicationBundleIdentifiers: Set<String> = []
    ) {
        self.selection = selection
        self.alwaysBlockedSelection = alwaysBlockedSelection
        self.allowedSystemApplicationBundleIdentifiers = allowedSystemApplicationBundleIdentifiers
    }
}
#endif
