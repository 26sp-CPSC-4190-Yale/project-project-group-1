import Foundation
import GroupActivities
import UnpluggedShared

struct UnpluggedRoomActivity: GroupActivity {
    let roomID: UUID

    static var activityIdentifier: String { "com.unplugged.room-join" }

    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = "Unplugged Room"
        meta.type = .generic
        return meta
    }
}

final class TouchTipsService: @unchecked Sendable {

    nonisolated(unsafe) var onRoomReceived: (@Sendable (UUID) -> Void)?

    private var listenTask: Task<Void, Never>?

    func activate(roomID: UUID) async throws {
        let activity = UnpluggedRoomActivity(roomID: roomID)
        _ = try await activity.activate()
    }

    func startListening() {
        listenTask?.cancel()
        listenTask = Task {
            for await session in UnpluggedRoomActivity.sessions() {
                let roomID = session.activity.roomID
                session.join()
                onRoomReceived?(roomID)
            }
        }
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
        onRoomReceived = nil
    }
}
