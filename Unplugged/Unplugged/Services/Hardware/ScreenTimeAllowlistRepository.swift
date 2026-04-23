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
        guard let archived = defaults?.data(forKey: key) else {
            return ScreenTimeAllowlistSnapshot(
                allowlist: ScreenTimeEmergencyAllowlist(),
                hasStoredValue: false
            )
        }

        do {
            let allowlist = try decoder.decode(ScreenTimeEmergencyAllowlist.self, from: archived)
            return ScreenTimeAllowlistSnapshot(allowlist: allowlist, hasStoredValue: true)
        } catch {
            // Fall through to legacy decode. Only worth logging if BOTH fail
            // — the current-schema decode failure is expected for data saved
            // before this shape existed.
        }

        do {
            let legacySelection = try decoder.decode(FamilyActivitySelection.self, from: archived)
            AppLogger.screenTime.info("allowlist decoded via legacy FamilyActivitySelection shape", context: ["bytes": archived.count])
            return ScreenTimeAllowlistSnapshot(
                allowlist: ScreenTimeEmergencyAllowlist(selection: legacySelection),
                hasStoredValue: true
            )
        } catch {
            // Both shapes failed. The user has stored data we can't read —
            // they'll see an empty allowlist and need to pick again.
            AppLogger.screenTime.error(
                "allowlist decode failed for both current and legacy schemas — resetting",
                error: error,
                context: ["bytes": archived.count]
            )
        }

        return ScreenTimeAllowlistSnapshot(
            allowlist: ScreenTimeEmergencyAllowlist(),
            hasStoredValue: true
        )
    }

    func save(_ allowlist: ScreenTimeEmergencyAllowlist) throws {
        do {
            let data = try encoder.encode(allowlist)
            defaults?.set(data, forKey: key)
        } catch {
            AppLogger.screenTime.error("allowlist encode failed — emergency apps not persisted", error: error)
            throw error
        }
    }
}
#endif
