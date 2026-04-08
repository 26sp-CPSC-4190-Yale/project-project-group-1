import Foundation

public protocol ProximityProviding: AnyObject, Sendable {
    var onDistanceUpdate: (@Sendable (Double?) -> Void)? { get set }
    var onRoomReceived: (@Sendable (UUID) -> Void)? { get set }
    func startAdvertising(roomID: UUID, userID: UUID)
    func startBrowsing(userID: UUID)
    func stop()
}
