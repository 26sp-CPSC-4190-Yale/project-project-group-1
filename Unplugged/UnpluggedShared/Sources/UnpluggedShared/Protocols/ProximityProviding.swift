import Foundation

public protocol ProximityProviding: AnyObject, Sendable {
    var onRoomReceived: (@Sendable (UUID) -> Void)? { get set }
    func activate(roomID: UUID) async throws
    func startListening()
    func stop()
}
