import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class JoinRoomViewModel {
    var isBrowsing = false
    var nearbyHostDistance: Double?
    var manualCode = ""
    var isJoining = false
    var joinedSession: SessionResponse?
    var error: String?

    var canJoinManually: Bool { !manualCode.isEmpty && !isJoining }

    func startBrowsing(touchTips: TouchTipsService, userID: UUID, sessions: SessionAPIService) {
        isBrowsing = true
        let vm = self
        touchTips.onDistanceUpdate = { dist in
            Task { @MainActor in vm.nearbyHostDistance = dist }
        }
        touchTips.onRoomReceived = { roomID in
            Task { @MainActor in
                await vm.join(code: roomID.uuidString, sessions: sessions)
            }
        }
        touchTips.startBrowsing(userID: userID)
    }

    func stopBrowsing(touchTips: TouchTipsService) {
        touchTips.stop()
        isBrowsing = false
    }

    func joinWithCode(sessions: SessionAPIService) async {
        let trimmed = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Enter a room code"
            return
        }
        await join(code: trimmed, sessions: sessions)
    }

    private func join(code: String, sessions: SessionAPIService) async {
        guard !isJoining else { return }
        isJoining = true
        error = nil
        do {
            joinedSession = try await sessions.joinSession(code: code)
        } catch {
            self.error = "Failed to join room"
        }
        isJoining = false
    }
}
