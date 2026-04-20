import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class CreateRoomViewModel {
    var roomName = ""
    /// Minutes selected from the duration picker.
    var selectedDuration: Int = 60
    let durationOptions = [30, 60, 90, 120]

    var isCreating = false
    var isAdvertising = false
    var createdSession: SessionResponse?
    var error: String?

    var canCreate: Bool { !roomName.isEmpty && !isCreating }

    func createRoom(sessions: SessionAPIService) async {
        isCreating = true
        error = nil
        do {
            createdSession = try await sessions.createSession(
                title: roomName,
                durationSeconds: selectedDuration * 60,
                location: nil
            )
        } catch {
            self.error = "Failed to create room"
        }
        isCreating = false
    }

    func startAdvertising(touchTips: TouchTipsService, roomID: UUID) async {
        isAdvertising = true
        do {
            try await touchTips.activate(roomID: roomID)
        } catch {
            self.error = "Failed to start sharing"
            isAdvertising = false
        }
    }

    func stopAdvertising(touchTips: TouchTipsService) {
        Task { await touchTips.stop() }
        isAdvertising = false
    }
}
