import Foundation
#if canImport(FamilyControls)
import FamilyControls

struct ScreenTimeAllowlistSnapshot {
    let allowlist: ScreenTimeEmergencyAllowlist
    let hasStoredValue: Bool
}

actor ScreenTimeAllowlistRepository {
    private let defaults: UserDefaults?
    private let key: String
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()

    init(defaults: UserDefaults?, key: String) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> ScreenTimeAllowlistSnapshot {
        let span = ResponsivenessDiagnostics.begin("allowlist_decode")
        defer { span.end() }

        guard let archived = defaults?.data(forKey: key) else {
            return ScreenTimeAllowlistSnapshot(
                allowlist: ScreenTimeEmergencyAllowlist(),
                hasStoredValue: false
            )
        }

        if let allowlist = try? decoder.decode(
            ScreenTimeEmergencyAllowlist.self,
            from: archived
        ) {
            return ScreenTimeAllowlistSnapshot(
                allowlist: allowlist,
                hasStoredValue: true
            )
        }

        if let legacySelection = try? decoder.decode(
            FamilyActivitySelection.self,
            from: archived
        ) {
            return ScreenTimeAllowlistSnapshot(
                allowlist: ScreenTimeEmergencyAllowlist(selection: legacySelection),
                hasStoredValue: true
            )
        }

        return ScreenTimeAllowlistSnapshot(
            allowlist: ScreenTimeEmergencyAllowlist(),
            hasStoredValue: true
        )
    }

    func save(_ allowlist: ScreenTimeEmergencyAllowlist) throws {
        let span = ResponsivenessDiagnostics.begin("allowlist_encode")
        defer { span.end() }

        let data = try encoder.encode(allowlist)
        defaults?.set(data, forKey: key)
    }
}
#endif
