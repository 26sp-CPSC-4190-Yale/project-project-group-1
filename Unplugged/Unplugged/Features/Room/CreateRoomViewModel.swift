import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class CreateRoomViewModel {
    var roomName = ""
    var selectedDuration: Int = 60
    let durationOptions = [30, 60, 90, 120]

    var isCreating = false
    var isAdvertising = false
    var nearbyJoinerDistance: Double?
    var createdSession: SessionResponse?
    var error: String?

    var canCreate: Bool { !roomName.isEmpty && !isCreating }

    func createRoom(sessions: SessionAPIService) async {
        isCreating = true
        error = nil
        do {
            createdSession = try await sessions.createSession()
        } catch {
            self.error = "Failed to create room"
        }
        isCreating = false
    }

    func startAdvertising(touchTips: TouchTipsService, roomID: UUID, userID: UUID) {
        isAdvertising = true
        let vm = self
        touchTips.onDistanceUpdate = { dist in
            Task { @MainActor in vm.nearbyJoinerDistance = dist }
        }
        touchTips.startAdvertising(roomID: roomID, userID: userID)
    }

    func stopAdvertising(touchTips: TouchTipsService) {
        touchTips.stop()
        isAdvertising = false
    }
}
