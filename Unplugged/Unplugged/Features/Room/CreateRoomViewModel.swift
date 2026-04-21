import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class CreateRoomViewModel {
    /// Minutes selected from the duration picker.
    var selectedDuration: Int = 60
    let durationOptions = [30, 60, 90, 120]

    var isCreating = false
    var createdSession: SessionResponse?
    var error: String?

    func createRoom(title: String, sessions: SessionAPIService) async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }

        error = nil
        createdSession = nil
        let span = ResponsivenessDiagnostics.begin("create_room_tap")
        defer { span.end() }

        do {
            createdSession = try await sessions.createSession(
                title: title,
                durationSeconds: selectedDuration * 60,
                location: nil
            )
            ResponsivenessDiagnostics.event("create_room_response")
        } catch is CancellationError {
            createdSession = nil
        } catch {
            guard !Task.isCancelled else {
                createdSession = nil
                return
            }
            self.error = "Failed to create room: \(Self.errorMessage(for: error))"
        }
    }

    private static func errorMessage(for error: Error) -> String {
        let message = (error as NSError).localizedDescription
        return message.isEmpty ? "Unknown error" : message
    }
}
