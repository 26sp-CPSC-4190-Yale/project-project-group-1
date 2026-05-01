import DeviceActivity
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: .init(ScreenTimeShared.managedSettingsStoreName))

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        guard activity.rawValue == ScreenTimeShared.deviceActivityName,
              let context = ScreenTimeShared.loadActiveContext(),
              context.isExpired() else {
            return
        }

        clearShield()
        ScreenTimeShared.clearActiveContext()
        DeviceActivityCenter().stopMonitoring([activity])
    }

    private func clearShield() {
        store.application.blockedApplications = nil
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
        store.webContent.blockedByFilter = nil
    }
}
