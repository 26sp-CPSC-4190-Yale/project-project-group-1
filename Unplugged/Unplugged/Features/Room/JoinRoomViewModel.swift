import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class JoinRoomViewModel {
    var isListening = false
    var hasFoundRoom = false
    // normalization happens at the binding boundary (see JoinRoomView), not in didSet,
    // so we never re-publish on the same observation tick and SwiftUI re-renders once per keystroke
    var manualCode = ""
    var isJoining = false
    var joinedSession: SessionResponse?
    var error: String?

    private var listenTask: Task<Void, Never>?
    private let haptics = HapticsService()

    var canJoinManually: Bool {
        InputValidation.isValidSessionCode(manualCode) && !isJoining
    }

    func startListening(touchTips: TouchTipsService, sessions: SessionAPIService) {
        guard !isListening else { return }
        isListening = true
        hasFoundRoom = false
        _ = AppLogger.measureMainThreadWork(
            "JoinRoomViewModel.prepareHaptics",
            category: .ui,
            warnAfter: 0.02
        ) {
            haptics.prepareTap()
        }

        listenTask?.cancel()
        listenTask = Task { [weak self] in
            let stream = await touchTips.startListening()
            for await roomID in stream {
                guard let self, !Task.isCancelled else { return }
                self.hasFoundRoom = true
                AppLogger.measureMainThreadWork(
                    "JoinRoomViewModel.fireHaptic",
                    category: .ui,
                    warnAfter: 0.02
                ) {
                    self.haptics.playTap()
                }
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

    func stopListeningNow(touchTips: TouchTipsService) async {
        listenTask?.cancel()
        listenTask = nil
        await touchTips.stop()
        isListening = false
        hasFoundRoom = false
    }

    func joinRoom(id: UUID, sessions: SessionAPIService) async {
        guard !isJoining else { return }
        isJoining = true
        defer { isJoining = false }

        error = nil

        do {
            joinedSession = try await sessions.joinSession(id: id)
        } catch is CancellationError {
            joinedSession = nil
        } catch {
            guard !Task.isCancelled else {
                joinedSession = nil
                return
            }
            AppLogger.room.error("joinSession(id) failed", error: error, context: ["id": id.uuidString])
            self.error = Self.joinErrorMessage(for: error)
        }
    }

    func joinWithCode(sessions: SessionAPIService, touchTips: TouchTipsService) async {
        let code = Self.normalizedRoomCode(manualCode)
        manualCode = code
        guard InputValidation.isValidSessionCode(code) else {
            error = "Enter a 6-character room code"
            return
        }

        guard !isJoining else { return }
        isJoining = true
        defer { isJoining = false }

        await stopListeningNow(touchTips: touchTips)
        error = nil

        do {
            joinedSession = try await sessions.joinSession(code: code)
        } catch is CancellationError {
            joinedSession = nil
        } catch {
            guard !Task.isCancelled else {
                joinedSession = nil
                return
            }
            AppLogger.room.error("joinSession(code) failed", error: error, context: ["code_len": code.count])
            self.error = Self.joinErrorMessage(for: error)
        }
    }

    static func normalizedRoomCode(_ code: String) -> String {
        String(code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isLetter || $0.isNumber }
            .prefix(InputValidation.sessionCodeLength))
            .uppercased()
    }

    private static func joinErrorMessage(for error: Error) -> String {
        if (error as? URLError)?.code == .timedOut {
            return "Joining timed out. Check your connection and try again."
        }
        return "Failed to join room"
    }
}
