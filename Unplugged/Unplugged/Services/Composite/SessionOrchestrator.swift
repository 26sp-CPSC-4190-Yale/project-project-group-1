//
//  SessionOrchestrator.swift
//  UnpluggedServices.Composite
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Observation
import UnpluggedShared

/// Top-level coordinator that owns the "currently active" session on this device.
///
/// Responsibilities:
///  - drive session start/end over the REST API
///  - subscribe to the WebSocket for real-time lifecycle events
///  - engage/disengage the Screen Time shield when lock events arrive
///  - feed observable state (countdownEndsAt, isLocked, participants) to SwiftUI
///  - poll for jailbreak (user clearing Screen Time auth) while locked
@MainActor
@Observable
final class SessionOrchestrator {
    enum LifecyclePhase: Sendable {
        case idle
        case lobby
        case locked
        case ended
    }

    var phase: LifecyclePhase = .idle
    var currentSession: SessionResponse?
    var participants: [ParticipantResponse] = []
    var countdownEndsAt: Date?
    var errorMessage: String?
    var lastRecap: SessionRecapResponse?

    private let sessions: SessionAPIService
    private let recap: RecapAPIService
    private let screenTime: ScreenTimeService
    private let cache: LocalCacheService
    private let webSocket: WebSocketClient

    private var listenerTask: Task<Void, Never>?
    private var jailbreakWatchdog: Task<Void, Never>?

    init(sessions: SessionAPIService,
         recap: RecapAPIService,
         screenTime: ScreenTimeService,
         cache: LocalCacheService,
         webSocket: WebSocketClient) {
        self.sessions = sessions
        self.recap = recap
        self.screenTime = screenTime
        self.cache = cache
        self.webSocket = webSocket
    }

    // MARK: - Entry points

    /// Called after a host or guest has a `SessionResponse` in hand. Puts the device
    /// into lobby mode and opens the WebSocket.
    func enterLobby(session: SessionResponse) async {
        self.currentSession = session
        self.participants = session.participants
        self.phase = session.session.lockedAt == nil ? .lobby : .locked
        self.countdownEndsAt = session.session.endsAt
        await connectWebSocket(sessionID: session.session.id)
    }

    /// Host-only. Tells the server to lock the room for all members. The server will
    /// broadcast `sessionLocked` which this orchestrator will handle via the WS stream.
    func hostStart() async {
        guard let session = currentSession else { return }
        do {
            let updated = try await sessions.startSession(id: session.session.id)
            self.currentSession = updated
            if let endsAt = updated.session.endsAt {
                self.countdownEndsAt = endsAt
                self.phase = .locked
                await engageShield(endsAt: endsAt)
            }
        } catch {
            errorMessage = "Couldn't start the session: \(error)"
        }
    }

    /// Host-only. Tells the server to end the room. Server broadcasts `sessionEnded`
    /// which will clear the shield and load the recap.
    func hostEnd() async {
        guard let session = currentSession else { return }
        do {
            _ = try await sessions.endSession(id: session.session.id)
        } catch {
            errorMessage = "Couldn't end the session."
        }
    }

    /// Called from `AppDelegate` when a silent APNs push arrives. Silent push is the
    /// fallback path when the WebSocket isn't connected (app suspended/killed).
    func applyRemoteLock(endsAt: Date) async {
        self.countdownEndsAt = endsAt
        self.phase = .locked
        await engageShield(endsAt: endsAt)
    }

    func handleRemotePayload(type: String, userInfo: [AnyHashable: Any]) {
        switch type {
        case "session_locked":
            if let iso = userInfo["endsAt"] as? String,
               let endsAt = ISO8601DateFormatter().date(from: iso) {
                Task { await applyRemoteLock(endsAt: endsAt) }
            }
        case "session_ended":
            Task { await handleSessionEnded() }
        default:
            break
        }
    }

    // MARK: - WebSocket plumbing

    private func connectWebSocket(sessionID: UUID) async {
        guard let token = cache.readToken() else { return }
        listenerTask?.cancel()
        let stream = await webSocket.connect(sessionID: sessionID, token: token)
        listenerTask = Task { [weak self] in
            for await message in stream {
                guard let self else { return }
                await self.handle(message: message)
            }
        }
    }

    private func handle(message: WSServerMessage) async {
        switch message {
        case .participantJoined(let p):
            if !participants.contains(where: { $0.id == p.id }) {
                participants.append(p)
            }
        case .participantLeft(let userID):
            participants.removeAll { $0.userID == userID }
        case .sessionStarted(let endsAt), .sessionLocked(let endsAt):
            self.countdownEndsAt = endsAt
            self.phase = .locked
            await engageShield(endsAt: endsAt)
        case .sessionEnded:
            await handleSessionEnded()
        case .stateSync(let response):
            self.currentSession = response
            self.participants = response.participants
            if let endsAt = response.session.endsAt {
                self.countdownEndsAt = endsAt
            }
            if response.session.endedAt != nil {
                self.phase = .ended
            } else if response.session.lockedAt != nil {
                self.phase = .locked
            } else {
                self.phase = .lobby
            }
        case .jailbreakReported:
            break
        case .error(let message):
            self.errorMessage = message
        }
    }

    // MARK: - Shield + recap

    private func engageShield(endsAt: Date) async {
        do {
            try await screenTime.lockApps(endsAt: endsAt)
        } catch {
            errorMessage = "Couldn't engage the shield."
        }
        startJailbreakWatchdog()
    }

    private func handleSessionEnded() async {
        stopJailbreakWatchdog()
        try? await screenTime.unlockApps()
        self.phase = .ended
        if let id = currentSession?.session.id {
            do {
                self.lastRecap = try await recap.getRecap(sessionID: id)
            } catch {
                // Recap may not be available immediately; the recap screen will retry.
            }
        }
        listenerTask?.cancel()
        listenerTask = nil
        await webSocket.disconnect()
    }

    // MARK: - Jailbreak watchdog

    private func startJailbreakWatchdog() {
        jailbreakWatchdog?.cancel()
        guard let sessionID = currentSession?.session.id else { return }
        jailbreakWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self else { return }
                if !(await self.isShieldStillAuthorized()) {
                    try? await self.sessions.reportJailbreak(
                        id: sessionID,
                        reason: "screen_time_auth_cleared")
                    try? await self.webSocket.send(
                        .reportJailbreak(reason: "screen_time_auth_cleared"))
                    return
                }
            }
        }
    }

    private func stopJailbreakWatchdog() {
        jailbreakWatchdog?.cancel()
        jailbreakWatchdog = nil
    }

    private func isShieldStillAuthorized() async -> Bool {
        screenTime.isAuthorized || !screenTime.isAvailable
    }
}
