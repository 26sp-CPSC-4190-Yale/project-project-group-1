import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class CreateRoomViewModel {
    var duration = DurationValue(hours: 1, minutes: 0, isUnlimited: false)

    // lives here so subviews can read it without invalidating CreateRoomView.body on every keystroke, which was re-rendering the duration picker
    var roomName: String = ""

    var isCreating = false
    var createdSession: SessionResponse?
    var error: String?

    var trimmedRoomName: String {
        roomName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canCreate: Bool {
        !trimmedRoomName.isEmpty && !isCreating
    }

    func createRoom(title: String, sessions: SessionAPIService) async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }

        error = nil
        createdSession = nil

        do {
            createdSession = try await sessions.createSession(
                title: title,
                durationSeconds: duration.durationSeconds,
                location: nil
            )
        } catch is CancellationError {
            createdSession = nil
        } catch {
            guard !Task.isCancelled else {
                createdSession = nil
                return
            }
            AppLogger.room.error(
                "createRoom failed",
                error: error,
                context: ["has_title": !title.isEmpty]
            )
            self.error = "Failed to create room: \(Self.errorMessage(for: error))"
        }
    }

    private static func errorMessage(for error: Error) -> String {
        let message = (error as NSError).localizedDescription
        return message.isEmpty ? "Unknown error" : message
    }
}
