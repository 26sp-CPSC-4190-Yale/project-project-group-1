import Foundation
#if canImport(FamilyControls)
@preconcurrency import FamilyControls
#endif

#if canImport(FamilyControls)
nonisolated struct ScreenTimeEmergencyAllowlist: Codable, Equatable, Sendable {
    var selection: FamilyActivitySelection
    var allowedSystemApplicationBundleIdentifiers: Set<String>

    init(
        selection: FamilyActivitySelection = FamilyActivitySelection(includeEntireCategory: false),
        allowedSystemApplicationBundleIdentifiers: Set<String> = []
    ) {
        self.selection = selection
        self.allowedSystemApplicationBundleIdentifiers = allowedSystemApplicationBundleIdentifiers
    }
}
#endif
