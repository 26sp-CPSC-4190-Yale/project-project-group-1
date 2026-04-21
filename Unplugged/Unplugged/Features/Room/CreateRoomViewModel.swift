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
            self.error = "Failed to create room: \(Self.errorMessage(for: error))"
        }
        isCreating = false
    }

    private static func errorMessage(for error: Error) -> String {
        let message = (error as NSError).localizedDescription
        return message.isEmpty ? "Unknown error" : message
    }
}
