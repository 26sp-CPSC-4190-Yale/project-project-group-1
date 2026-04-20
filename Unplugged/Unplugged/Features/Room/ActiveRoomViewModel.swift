import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
final class ActiveRoomViewModel {
    let isHost: Bool
    var showEndConfirmation = false
    var showRecap = false

    init(isHost: Bool) {
        self.isHost = isHost
    }

    func isHost(orchestrator: SessionOrchestrator) -> Bool {
        return isHost
    }

    func start(orchestrator: SessionOrchestrator) async {
        await orchestrator.hostStart()
    }

    func end(orchestrator: SessionOrchestrator) async {
        await orchestrator.hostEnd()
    }
}
