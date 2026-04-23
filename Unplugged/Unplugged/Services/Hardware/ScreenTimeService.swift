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
    #endif

    init() {
        let defaults = UserDefaults(suiteName: Self.appGroup)
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
        guard isAvailable else { return }
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
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
        guard isAvailable, isAuthorized else { return }
        let span = ResponsivenessDiagnostics.begin("screentime_lock")
        defer { span.end() }

        let allowlist = (await allowlistRepository.load()).allowlist
        let emergencySelection = allowlist.selection
        let allowedAppTokens = emergencySelection.applicationTokens
        let allowedWebDomains = emergencySelection.webDomains

        // Do not use ApplicationSettings.blockedApplications for session locking.
        // That API hides apps from the Home Screen and iOS can restore them in a
        // different order afterward. Shield settings block access without mutating
        // the user's Home Screen layout.
        store.application.blockedApplications = nil
        await Task.yield()
        store.shield.applications = nil
        await Task.yield()
        store.shield.webDomains = nil
        await Task.yield()
        store.shield.applicationCategories = .all(except: allowedAppTokens)
        await Task.yield()
        store.shield.webDomainCategories = .all(except: emergencySelection.webDomainTokens)
        await Task.yield()
        store.webContent.blockedByFilter = .all(except: allowedWebDomains)
        await Task.yield()

        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute, .second], from: Date())
        let end = calendar.dateComponents([.hour, .minute, .second], from: endsAt)
        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: false
        )

        center.stopMonitoring([activityName])
        await Task.yield()
        try center.startMonitoring(activityName, during: schedule)
        #endif
    }

    func unlockApps() async throws {
        #if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
        guard isAvailable else { return }
        let span = ResponsivenessDiagnostics.begin("screentime_unlock")
        defer { span.end() }

        store.application.blockedApplications = nil
        await Task.yield()
        store.shield.applications = nil
        await Task.yield()
        store.shield.applicationCategories = nil
        await Task.yield()
        store.shield.webDomains = nil
        await Task.yield()
        store.shield.webDomainCategories = nil
        await Task.yield()
        store.webContent.blockedByFilter = nil
        await Task.yield()
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
    #endif
}
