import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
final class ActiveRoomViewModel {
    let isHost: Bool
    var showEndConfirmation = false
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

        await Task.yield()
        await orchestrator.enterLobby(session: session)

        guard isHost else { return }
        // Fire TouchTips activation off the main actor. MC/NI framework calls
        // (MCSession init, startAdvertisingPeer) are heavyweight and stall the
        // main thread 200-300ms when awaited inline. Running in a detached Task
        // lets the lobby UI render immediately.
        Task.detached { [sessionID] in
            let span = ResponsivenessDiagnostics.begin("touchtips_activate")
            defer { span.end() }
            try? await touchTips.activate(roomID: sessionID)
        }
    }

    func start(orchestrator: SessionOrchestrator) async {
        await orchestrator.hostStart()
    }

    func end(orchestrator: SessionOrchestrator) async {
        await orchestrator.hostEnd()
    }
}
