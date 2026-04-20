import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
final class ActiveRoomViewModel {
    let currentUserID: UUID
    var showEndConfirmation = false
    var showRecap = false

    init(currentUserID: UUID) {
        self.currentUserID = currentUserID
    }

    func isHost(orchestrator: SessionOrchestrator) -> Bool {
        orchestrator.currentSession?.session.hostID == currentUserID
    }

    func start(orchestrator: SessionOrchestrator) async {
        await orchestrator.hostStart()
    }

    func end(orchestrator: SessionOrchestrator) async {
        await orchestrator.hostEnd()
    }
}
