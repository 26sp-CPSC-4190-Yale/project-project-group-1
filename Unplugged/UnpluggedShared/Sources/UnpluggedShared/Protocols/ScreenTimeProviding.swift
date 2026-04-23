import Foundation

public protocol ScreenTimeProviding: AnyObject, Sendable {
    var isAuthorized: Bool { get }
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func setEmergencyAllowlist(_ archivedSelection: Data)
    func loadEmergencyAllowlist() -> Data?
    func lockApps(endsAt: Date) async throws
    func unlockApps() async throws
}
