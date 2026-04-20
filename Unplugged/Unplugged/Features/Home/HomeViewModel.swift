import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class HomeViewModel {
    var showJoinRoom = false
    var showCreateRoom = false
    var activeSession: SessionResponse?
    var isHost = false
}
