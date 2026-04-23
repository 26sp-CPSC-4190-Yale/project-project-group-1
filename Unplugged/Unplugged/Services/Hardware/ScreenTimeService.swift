//
//  ScreenTimeService.swift
//  Unplugged.Services.Hardware
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import UnpluggedShared
#if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
import FamilyControls
import ManagedSettings
import DeviceActivity
#endif

/// Wraps FamilyControls + ManagedSettings + DeviceActivity so the rest of the app can
/// engage the "unplugged" shield without caring whether the entitlement is present.
///
/// On a paid Apple Developer account with the Family Controls entitlement approved this
/// issues a real `ManagedSettingsStore.shield` and schedules a DeviceActivity monitor
/// so the shield clears at `endsAt` even if the app is killed. Without the entitlement
/// (free account, Simulator, missing permission) every call no-ops and the service
/// advertises `isAvailable == false` so the UI can degrade gracefully.
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
            // App Group not provisioned — the shield extension cannot share
            // the allowlist with the main app. This only fails when the
            // entitlements plist and dev portal are misconfigured.
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

        // Apple's built-in apps aren't covered by ActivityCategoryPolicy.all(except:)
        // — their tokens can't be derived from a bundle ID, and many aren't in a
        // shieldable category. blockedApplications is the only API that can stop
        // them from launching, and it accepts Application(bundleIdentifier:). The
        // home-screen-reorder side effect is acceptable; letting Apple apps through
        // defeats the session lock.
        let blockedSystemApplications: Set<Application> = Set(
            EmergencySystemApplication.allCases
                .filter { !allowedSystemBundleIDs.contains($0.bundleIdentifier) }
                .map { Application(bundleIdentifier: $0.bundleIdentifier) }
        )

        store.application.blockedApplications = blockedSystemApplications.isEmpty ? nil : blockedSystemApplications
        store.shield.applications = nil
        store.shield.webDomains = nil
        store.shield.applicationCategories = .all(except: allowedAppTokens)
        store.shield.webDomainCategories = .all(except: emergencySelection.webDomainTokens)
        store.webContent.blockedByFilter = .all(except: allowedWebDomains)

        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute, .second], from: Date())
        let end = calendar.dateComponents([.hour, .minute, .second], from: endsAt)
        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: false
        )

        center.stopMonitoring([activityName])
        do {
            try center.startMonitoring(activityName, during: schedule)
        } catch {
            // DeviceActivity monitoring failure means the shield won't
            // auto-clear at endsAt even if lockApps otherwise succeeded.
            // That strands the user past the session — log loudly.
            AppLogger.screenTime.critical(
                "DeviceActivityCenter.startMonitoring failed — shield will not auto-clear",
                error: error,
                context: ["endsAt": ISO8601DateFormatter().string(from: endsAt)]
            )
            throw error
        }
        AppLogger.breadcrumb(.screenTime, "lock_end")
        #endif
    }

    func unlockApps() async throws {
        #if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
        guard isAvailable else { return }
        store.application.blockedApplications = nil
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
        store.webContent.blockedByFilter = nil
        center.stopMonitoring([activityName])
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
