import Foundation
import UnpluggedShared
#if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
import FamilyControls
import ManagedSettings
import DeviceActivity
#endif

// all calls no-op and isAvailable is false when the FamilyControls entitlement is missing, on simulator, or permission is denied
final class ScreenTimeService: ScreenTimeProviding, @unchecked Sendable {
    static let appGroup = "group.com.unplugged.app.shared"
    static let allowlistKey = "emergencyAllowlist"
    static let monitorName = "unpluggedSession"
    static let storeName = "unpluggedSession"

    private let groupDefaults: UserDefaults?

    #if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
    private let allowlistRepository: ScreenTimeAllowlistRepository
    private let store = ManagedSettingsStore(named: .init(ScreenTimeService.storeName))
    private let center = DeviceActivityCenter()
    private let activityName = DeviceActivityName(ScreenTimeService.monitorName)

    enum ScreenTimeServiceError: LocalizedError {
        case unavailable
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Screen Time is unavailable on this device."
            case .notAuthorized:
                return "Screen Time permission is not approved."
            }
        }
    }
    #endif

    init() {
        let defaults = UserDefaults(suiteName: Self.appGroup)
        if defaults == nil {
            AppLogger.screenTime.critical(
                "App Group UserDefaults unavailable — allowlist will not be shared with shield extension",
                context: ["suite": Self.appGroup]
            )
        }
        self.groupDefaults = defaults
        #if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
        self.allowlistRepository = ScreenTimeAllowlistRepository(
            defaults: defaults,
            key: Self.allowlistKey
        )
        #endif
    }

    var isAvailable: Bool {
        #if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
        #else
        return false
        #endif
    }

    var isAuthorized: Bool {
        #if canImport(FamilyControls)
        guard isAvailable else { return false }
        return AuthorizationCenter.shared.authorizationStatus == .approved
        #else
        return false
        #endif
    }

    func requestAuthorization() async throws {
        #if canImport(FamilyControls)
        guard isAvailable else {
            AppLogger.screenTime.info("requestAuthorization no-op: isAvailable=false")
            return
        }
        AppLogger.breadcrumb(.screenTime, "request_authorization_begin")
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            AppLogger.screenTime.error("AuthorizationCenter.requestAuthorization threw", error: error)
            throw error
        }
        await waitForAuthorizationStatusPropagation()
        AppLogger.breadcrumb(.screenTime, "request_authorization_end", context: ["authorized": isAuthorized])
        #else
        return
        #endif
    }

    func setEmergencyAllowlist(_ archivedSelection: Data) {
        groupDefaults?.set(archivedSelection, forKey: Self.allowlistKey)
    }

    func loadEmergencyAllowlist() -> Data? {
        groupDefaults?.data(forKey: Self.allowlistKey)
    }

    func lockApps(endsAt: Date) async throws {
        #if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
        guard isAvailable else {
            AppLogger.screenTime.warning("lockApps failed — ScreenTime unavailable on device")
            throw ScreenTimeServiceError.unavailable
        }
        AppLogger.breadcrumb(.screenTime, "lock_begin", context: ["endsAt": ISO8601DateFormatter().string(from: endsAt)])
        try await ensureAuthorized()

        let allowlist = (await allowlistRepository.load()).allowlist
        let emergencySelection = allowlist.selection
        let allowedAppTokens = emergencySelection.applicationTokens
        let allowedWebDomains = emergencySelection.webDomains
        let allowedSystemBundleIDs = allowlist.allowedSystemApplicationBundleIdentifiers

        let now = Date()
        // DeviceActivitySchedule requires >= 15 min window, pad short sessions to 16, the normal unlock flow clears the shield at the real endsAt well before the monitor fires
        let scheduledEndsAt = max(endsAt, now.addingTimeInterval(16 * 60))
        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute, .second], from: now)
        let end = calendar.dateComponents([.hour, .minute, .second], from: scheduledEndsAt)
        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: false
        )

        AppLogger.measureMainThreadWork(
            "ScreenTimeService.stopMonitoringBeforeLock",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            center.stopMonitoring([activityName])
        }
        var monitoringFailed = false
        do {
            try AppLogger.measureMainThreadWork(
                "ScreenTimeService.startMonitoring",
                category: .screenTime,
                warnAfter: 0.03
            ) {
                try center.startMonitoring(activityName, during: schedule)
            }
        } catch {
            // do not throw, in-process enforcement still works and the user should not get a "couldn't engage shield" alert
            monitoringFailed = true
            AppLogger.screenTime.critical(
                "DeviceActivityCenter.startMonitoring failed — shield will not auto-clear",
                error: error,
                context: [
                    "endsAt": ISO8601DateFormatter().string(from: endsAt),
                    "scheduledEndsAt": ISO8601DateFormatter().string(from: scheduledEndsAt)
                ]
            )
        }

        // ActivityCategoryPolicy does not cover Apple's built-in apps, blockedApplications is the only API that can stop them, home-screen reorder is the tradeoff
        let blockedSystemApplications: Set<Application> = Set(
            EmergencySystemApplication.allCases
                .filter { !allowedSystemBundleIDs.contains($0.bundleIdentifier) }
                .map { Application(bundleIdentifier: $0.bundleIdentifier) }
        )

        // yield between FamilyControls writes to keep the main thread responsive during the IPC burst
        AppLogger.measureMainThreadWork(
            "ScreenTimeService.blockedApplications.set",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            store.application.blockedApplications = blockedSystemApplications.isEmpty ? nil : blockedSystemApplications
        }
        await Task.yield()
        AppLogger.measureMainThreadWork(
            "ScreenTimeService.shieldApplications.clear",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            store.shield.applications = nil
        }
        await Task.yield()
        AppLogger.measureMainThreadWork(
            "ScreenTimeService.shieldWebDomains.clear",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            store.shield.webDomains = nil
        }
        await Task.yield()
        AppLogger.measureMainThreadWork(
            "ScreenTimeService.applicationCategories.set",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            store.shield.applicationCategories = .all(except: allowedAppTokens)
        }
        await Task.yield()
        AppLogger.measureMainThreadWork(
            "ScreenTimeService.webDomainCategories.set",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            store.shield.webDomainCategories = .all(except: emergencySelection.webDomainTokens)
        }
        await Task.yield()
        AppLogger.measureMainThreadWork(
            "ScreenTimeService.webContentFilter.set",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            store.webContent.blockedByFilter = .all(except: allowedWebDomains)
        }

        AppLogger.breadcrumb(
            .screenTime,
            "lock_end",
            context: ["monitoringFailed": monitoringFailed]
        )
        #endif
    }

    func unlockApps() async throws {
        #if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
        guard isAvailable else { return }

        AppLogger.measureMainThreadWork(
            "ScreenTimeService.blockedApplications.clear",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            store.application.blockedApplications = nil
        }
        await Task.yield()
        AppLogger.measureMainThreadWork(
            "ScreenTimeService.shieldApplications.clear",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            store.shield.applications = nil
        }
        await Task.yield()
        AppLogger.measureMainThreadWork(
            "ScreenTimeService.applicationCategories.clear",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            store.shield.applicationCategories = nil
        }
        await Task.yield()
        AppLogger.measureMainThreadWork(
            "ScreenTimeService.shieldWebDomains.clear",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            store.shield.webDomains = nil
        }
        await Task.yield()
        AppLogger.measureMainThreadWork(
            "ScreenTimeService.webDomainCategories.clear",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            store.shield.webDomainCategories = nil
        }
        await Task.yield()
        AppLogger.measureMainThreadWork(
            "ScreenTimeService.webContentFilter.clear",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            store.webContent.blockedByFilter = nil
        }
        await Task.yield()
        AppLogger.measureMainThreadWork(
            "ScreenTimeService.stopMonitoringAfterUnlock",
            category: .screenTime,
            warnAfter: 0.03
        ) {
            center.stopMonitoring([activityName])
        }
        #endif
    }

    #if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
    func loadEmergencyAllowlistSnapshot() async -> ScreenTimeAllowlistSnapshot {
        await allowlistRepository.load()
    }

    func saveEmergencyAllowlist(_ allowlist: ScreenTimeEmergencyAllowlist) async throws {
        try await allowlistRepository.save(allowlist)
    }

    private func ensureAuthorized() async throws {
        if isAuthorized { return }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            AppLogger.screenTime.error("ensureAuthorized: requestAuthorization threw", error: error)
            throw error
        }
        await waitForAuthorizationStatusPropagation()
        guard isAuthorized else {
            AppLogger.screenTime.warning("ensureAuthorized: propagation timed out, still not authorized")
            throw ScreenTimeServiceError.notAuthorized
        }
    }

    private func waitForAuthorizationStatusPropagation() async {
        if isAuthorized { return }

        for _ in 0..<5 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if isAuthorized { return }
        }
    }
    #endif
}
