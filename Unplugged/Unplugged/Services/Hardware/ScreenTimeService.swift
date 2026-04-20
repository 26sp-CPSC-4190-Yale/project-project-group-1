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
    private let store = ManagedSettingsStore(named: .init(ScreenTimeService.storeName))
    private let center = DeviceActivityCenter()
    private let activityName = DeviceActivityName(ScreenTimeService.monitorName)
    #endif

    init() {
        self.groupDefaults = UserDefaults(suiteName: Self.appGroup)
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

        let allowedTokens: Set<ApplicationToken> = {
            guard let archived = loadEmergencyAllowlist() else { return [] }
            guard let selection = try? PropertyListDecoder().decode(
                FamilyActivitySelection.self, from: archived) else { return [] }
            return selection.applicationTokens
        }()

        store.shield.applications = nil
        store.shield.applicationCategories = .all(except: allowedTokens)
        store.shield.webDomainCategories = .all()

        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute, .second], from: Date())
        let end = calendar.dateComponents([.hour, .minute, .second], from: endsAt)
        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: false
        )

        center.stopMonitoring([activityName])
        try center.startMonitoring(activityName, during: schedule)
        #endif
    }

    func unlockApps() async throws {
        #if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
        guard isAvailable else { return }
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        center.stopMonitoring([activityName])
        #endif
    }
}
