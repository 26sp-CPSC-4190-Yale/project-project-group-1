import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class ActiveRoomViewModel {
    var session: SessionResponse
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

    func refresh(sessions: SessionAPIService) async {
        do {
            session = try await sessions.getSession(id: session.session.id)
        } catch {
            // leave stale state; refresh is best-effort
        }
    }
}
