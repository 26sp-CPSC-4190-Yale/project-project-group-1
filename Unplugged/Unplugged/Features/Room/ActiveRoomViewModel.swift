import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
final class ActiveRoomViewModel {
    let isHost: Bool
    var showEndConfirmation = false
    var showCloseConfirmation = false
    var showLeaveConfirmation = false
    var showRecap = false
    var isStartingLobby = false
    private var startedLobbySessionID: UUID?

    init(isHost: Bool) {
        self.isHost = isHost
    }

    func isHost(orchestrator: SessionOrchestrator) -> Bool {
        return isHost
    }

    func startLobbyIfNeeded(
        session: SessionResponse,
        orchestrator: SessionOrchestrator,
        touchTips: TouchTipsService
    ) async {
        let sessionID = session.session.id
        guard startedLobbySessionID != sessionID else { return }

        startedLobbySessionID = sessionID
        isStartingLobby = true
        defer { isStartingLobby = false }

        await orchestrator.enterLobby(session: session)

        guard isHost else { return }
        // MCSession init and startAdvertisingPeer stall the main actor for hundreds of ms, run off-actor
        Task.detached { [sessionID] in
            do {
                try await touchTips.activate(roomID: sessionID)
            } catch {
                AppLogger.room.error(
                    "touchTips.activate failed — host lobby cannot auto-pair",
                    error: error,
                    context: ["session": sessionID.uuidString]
                )
            }
        }
    }

    func start(orchestrator: SessionOrchestrator) async {
        await orchestrator.hostStart()
    }

    func end(orchestrator: SessionOrchestrator) async {
        await orchestrator.hostEnd()
    }
}
