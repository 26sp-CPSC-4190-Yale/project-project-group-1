import Foundation
import Observation
import UnpluggedShared
import UIKit

@MainActor
@Observable
class JoinRoomViewModel {
    var isListening = false
    var hasFoundRoom = false
    var manualCode = ""
    var isJoining = false
    var joinedSession: SessionResponse?
    var error: String?

    private var listenTask: Task<Void, Never>?

    var canJoinManually: Bool { !manualCode.isEmpty && !isJoining }

    func startListening(touchTips: TouchTipsService, sessions: SessionAPIService) {
        isListening = true
        hasFoundRoom = false

        listenTask?.cancel()
        listenTask = Task { [weak self] in
            let stream = await touchTips.startListening()
            for await roomID in stream {
                guard let self, !Task.isCancelled else { return }
                self.hasFoundRoom = true
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                #endif
                await self.joinRoom(id: roomID, sessions: sessions)
            }
        }
    }

    func stopListening(touchTips: TouchTipsService) {
        listenTask?.cancel()
        listenTask = nil
        Task { await touchTips.stop() }
        isListening = false
    }

    func joinRoom(id: UUID, sessions: SessionAPIService) async {
        guard !isJoining else { return }
        isJoining = true
        error = nil
        do {
            joinedSession = try await sessions.joinSession(id: id)
        } catch {
            self.error = "Failed to join room"
        }
        isJoining = false
    }

    func joinWithCode(sessions: SessionAPIService) async {
        let trimmed = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            error = "Invalid room code"
            return
        }

        guard !isJoining else { return }
        isJoining = true
        error = nil
        do {
            joinedSession = try await sessions.joinSession(code: trimmed)
        } catch {
            self.error = "Failed to join room"
        }
        isJoining = false
    }
}
