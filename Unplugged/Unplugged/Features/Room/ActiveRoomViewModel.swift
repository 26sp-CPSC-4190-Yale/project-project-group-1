import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class ActiveRoomViewModel {
    let session: SessionResponse
    let currentUserID: UUID
    var showEndConfirmation = false

    var isHost: Bool {
        session.session.hostID == currentUserID
    }

    var participants: [ParticipantResponse] {
        session.participants
    }

    init(session: SessionResponse, currentUserID: UUID) {
        self.session = session
        self.currentUserID = currentUserID
    }
}
