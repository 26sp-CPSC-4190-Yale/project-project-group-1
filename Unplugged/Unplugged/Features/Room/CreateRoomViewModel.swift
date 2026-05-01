import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class CreateRoomViewModel {
    var duration = DurationValue(hours: 1, minutes: 0, isUnlimited: false)

    // lives here so subviews can read it without invalidating CreateRoomView.body on every keystroke, which was re-rendering the duration picker
    var roomName: String = ""
    var description: String = ""
    var lockMode: SessionLockMode = .standard
    var includeLocation = false

    var isCreating = false
    var createdSession: SessionResponse?
    var error: String?

    var trimmedRoomName: String {
        roomName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canCreate: Bool {
        InputValidation.isValidSessionTitle(trimmedRoomName)
            && InputValidation.isValidSessionDescription(trimmedDescription)
            && InputValidation.isValidDurationSeconds(duration.durationSeconds)
            && !isCreating
    }

    func createRoom(title: String, sessions: SessionAPIService, location: LocationService? = nil) async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }

        error = nil
        createdSession = nil

        do {
            let locationSnapshot = includeLocation
                ? await location?.lockInSnapshot(requestPermissionIfNeeded: true)
                : nil
            createdSession = try await sessions.createSession(
                title: title,
                durationSeconds: duration.durationSeconds,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                lockMode: lockMode,
                location: locationSnapshot?.coordinate,
                weather: locationSnapshot?.weather
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
