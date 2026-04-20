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

actor TouchTipsService {

    private var listenTask: Task<Void, Never>?
    private var activeSession: GroupSession<UnpluggedRoomActivity>?
    private var continuation: AsyncStream<UUID>.Continuation?

    /// Returns an AsyncStream that yields room IDs as they are discovered via GroupActivities.
    /// Each call to `startListening()` vends a fresh stream; the previous one is finished.
    func roomDiscoveries() -> AsyncStream<UUID> {
        continuation?.finish()
        let stream = AsyncStream<UUID> { cont in
            self.continuation = cont
        }
        return stream
    }

    func activate(roomID: UUID) async throws {
        let activity = UnpluggedRoomActivity(roomID: roomID)
        _ = try await activity.activate()
    }

    func startListening() -> AsyncStream<UUID> {
        let stream = roomDiscoveries()

        listenTask?.cancel()
        listenTask = Task { [weak self] in
            for await session in UnpluggedRoomActivity.sessions() {
                guard let self else { return }
                await self.setActiveSession(session)
                let roomID = session.activity.roomID
                session.join()
                await self.yieldRoom(roomID)
            }
        }

        return stream
    }

    func stop() {
        activeSession?.leave()
        activeSession = nil

        listenTask?.cancel()
        listenTask = nil
        continuation?.finish()
        continuation = nil
    }

    private func setActiveSession(_ session: GroupSession<UnpluggedRoomActivity>) {
        self.activeSession = session
    }

    private func yieldRoom(_ roomID: UUID) {
        continuation?.yield(roomID)
    }
}
