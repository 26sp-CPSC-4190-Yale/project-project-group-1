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
    var proximityWarningSecondsRemaining: Int?
    var didLeaveCurrentSessionForProximity = false

    private let sessions: SessionAPIService
    private let recap: RecapAPIService
    private let screenTime: any ScreenTimeProviding
    private let cache: LocalCacheService
    private let webSocket: WebSocketClient
    private let touchTips: TouchTipsService

    private var listenerTask: Task<Void, Never>?
    private var jailbreakWatchdog: Task<Void, Never>?
    private var sessionSyncTask: Task<Void, Never>?
    private var lockedProximityUpdatesTask: Task<Void, Never>?
    private var lockedProximityCheckTask: Task<Void, Never>?
    private var proximityCountdownTask: Task<Void, Never>?
    private var lockedProximitySessionID: UUID?
    private var latestLockedProximityReading: LockedProximityReading?
    private var isReportingProximityExit = false
    private var lastShieldWarningSessionID: UUID?
    private var lastShieldWarningEndsAt: Date?
    private var lastShieldWarningMessage: String?
    private var appliedShieldSessionID: UUID?
    private var appliedShieldEndsAt: Date?

    init(sessions: SessionAPIService,
         recap: RecapAPIService,
         screenTime: any ScreenTimeProviding,
         cache: LocalCacheService,
         webSocket: WebSocketClient,
         touchTips: TouchTipsService) {
        self.sessions = sessions
        self.recap = recap
        self.screenTime = screenTime
        self.cache = cache
        self.webSocket = webSocket
        self.touchTips = touchTips
    }

    // MARK: - Entry points

    /// Called after a host or guest has a `SessionResponse` in hand. Puts the device
    /// into lobby mode and opens the WebSocket.
    func enterLobby(session: SessionResponse) async {
        let span = ResponsivenessDiagnostics.begin("enter_lobby")
        defer { span.end() }

        let shouldConnect = currentSession?.session.id != session.session.id
        await applySessionSnapshot(session)
        guard session.session.endedAt == nil else { return }
        guard shouldConnect else { return }
        await connectWebSocket(sessionID: session.session.id)
        startSessionSync(sessionID: session.session.id)
    }

    /// Host-only. Tells the server to lock the room for all members. The server will
    /// broadcast `sessionLocked` which this orchestrator will handle via the WS stream.
    func hostStart() async {
        guard let session = currentSession else { return }
        do {
            let updated = try await sessions.startSession(id: session.session.id)
            await applySessionSnapshot(updated)
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
    func applyRemoteLock(sessionID: UUID?, endsAt: Date) async {
        if let sessionID {
            startSessionSync(sessionID: sessionID)
            if let response = try? await sessions.getSession(id: sessionID) {
                await applySessionSnapshot(response)
                return
            }
        }
        await applyLocked(endsAt: endsAt)
    }

    func applyRemoteEnd(sessionID: UUID?) async {
        await handleSessionEnded()
    }

    /// Cancel all in-flight work (WebSocket listener, jailbreak watchdog) and close the
    /// socket. Called on logout, token invalidation, and any hard teardown path — the
    /// WS authenticates against a JWT and will fail once the token is gone, but holding
    /// the listener open spins indefinitely against a stale identity until the TCP drops.
    func teardown() async {
        stopJailbreakWatchdog()
        stopSessionSync()
        stopLockedProximityEnforcement()
        listenerTask?.cancel()
        listenerTask = nil
        await webSocket.disconnect()
        // §64: drop the Screen Time shield on teardown. If the user signs out
        // mid-session, leaving apps shielded with no session bound to them
        // strands the device — next launch shows a lock with no way to clear
        // it in-app. unlockApps is idempotent when nothing is shielded.
        try? await screenTime.unlockApps()
        phase = .idle
        currentSession = nil
        participants = []
        countdownEndsAt = nil
        errorMessage = nil
        lastRecap = nil
        didLeaveCurrentSessionForProximity = false
        resetShieldTracking()
    }

    func acknowledgeProximityExitDismissal() {
        didLeaveCurrentSessionForProximity = false
    }

    @discardableResult
    func handleRemotePayload(type: String, userInfo: [AnyHashable: Any]) async -> Bool {
        let sessionID = Self.payloadUUID(from: userInfo["sessionID"])
        switch type {
        case "session_locked":
            if let endsAt = Self.payloadDate(from: userInfo["endsAt"]) {
                await applyRemoteLock(sessionID: sessionID, endsAt: endsAt)
                return true
            }
        case "session_ended":
            await applyRemoteEnd(sessionID: sessionID)
            return true
        default:
            break
        }
        return false
    }

    // MARK: - WebSocket plumbing

    private func connectWebSocket(sessionID: UUID) async {
        guard let token = cache.readCachedToken() else { return }
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
            await applyLocked(endsAt: endsAt)
        case .sessionEnded:
            await handleSessionEnded()
        case .stateSync(let response):
            await applySessionSnapshot(response)
        case .jailbreakReported(let userID, let reason):
            if reason == "left_due_to_proximity" {
                participants.removeAll { $0.userID == userID }
            }
        case .participantLeftDueToProximity(let userID, let username):
            participants.removeAll { $0.userID == userID }
            if userID == cache.readUser()?.id {
                await completeLocalProximityExit()
            } else {
                errorMessage = "\(username) left the session because they were too far away."
            }
        case .error(let message):
            self.errorMessage = message
        }
    }

    // MARK: - State reconciliation

    private func startSessionSync(sessionID: UUID) {
        sessionSyncTask?.cancel()
        sessionSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.reconcileSession(sessionID: sessionID)
                let delay = await self.sessionSyncDelayNanos()
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func stopSessionSync() {
        sessionSyncTask?.cancel()
        sessionSyncTask = nil
    }

    private func sessionSyncDelayNanos() -> UInt64 {
        switch phase {
        case .idle, .lobby:
            3_000_000_000
        case .locked:
            15_000_000_000
        case .ended:
            15_000_000_000
        }
    }

    private func reconcileSession(sessionID: UUID) async {
        guard phase != .ended else {
            stopSessionSync()
            return
        }
        do {
            let response = try await sessions.getSession(id: sessionID)
            await applySessionSnapshot(response)
        } catch {
            // The WebSocket remains the primary real-time path; transient polling
            // failures should not block the room UI or spam alerts.
        }
    }

    private func applySessionSnapshot(_ response: SessionResponse) async {
        self.currentSession = response
        self.participants = response.participants.filter { $0.status == .active }
        self.countdownEndsAt = response.session.endsAt

        if let userID = cache.readUser()?.id,
           response.participants.contains(where: { $0.userID == userID && $0.status == .left }) {
            await completeLocalProximityExit()
            return
        }

        if response.session.endedAt != nil {
            await handleSessionEnded()
        } else if response.session.lockedAt != nil {
            self.phase = .locked
            if let endsAt = response.session.endsAt {
                await engageShield(endsAt: endsAt)
            } else {
                errorMessage = "This room is locked, but the server did not send an end time."
            }
            await startLockedProximityEnforcementIfNeeded()
        } else {
            self.phase = .lobby
            stopLockedProximityEnforcement()
        }
    }

    private func applyLocked(endsAt: Date) async {
        self.countdownEndsAt = endsAt
        self.phase = .locked
        await engageShield(endsAt: endsAt)
        await startLockedProximityEnforcementIfNeeded()
    }

    // MARK: - Shield + recap

    private func engageShield(endsAt: Date) async {
        let sessionID = currentSession?.session.id
        if shieldMatches(sessionID: sessionID, endsAt: endsAt, trackedSessionID: appliedShieldSessionID, trackedEndsAt: appliedShieldEndsAt) {
            startJailbreakWatchdog()
            return
        }

        guard endsAt > Date() else {
            setShieldWarning("This session has already ended.", sessionID: sessionID, endsAt: endsAt)
            return
        }

        guard screenTime.isAvailable else {
            setShieldWarning("Screen Time is unavailable on this device, so apps can't be blocked.", sessionID: sessionID, endsAt: endsAt)
            return
        }

        guard screenTime.isAuthorized else {
            setShieldWarning("Screen Time permission is required before Unplugged can lock apps.", sessionID: sessionID, endsAt: endsAt)
            return
        }

        do {
            try await screenTime.lockApps(endsAt: endsAt)
            appliedShieldSessionID = sessionID
            appliedShieldEndsAt = endsAt
            startJailbreakWatchdog()
        } catch {
            setShieldWarning("Couldn't engage the shield.", sessionID: sessionID, endsAt: endsAt)
        }
    }

    private func handleSessionEnded() async {
        stopJailbreakWatchdog()
        stopSessionSync()
        stopLockedProximityEnforcement()
        try? await screenTime.unlockApps()
        resetShieldTracking()
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

    // MARK: - Locked-room proximity enforcement

    private func startLockedProximityEnforcementIfNeeded() async {
        guard phase == .locked,
              let session = currentSession?.session,
              lockedProximitySessionID != session.id else { return }

        guard let userID = cache.readUser()?.id, userID != session.hostID else {
            stopLockedProximityEnforcement()
            return
        }

        guard await touchTips.supportsLockedProximityMonitoring() else {
            stopLockedProximityEnforcement()
            return
        }

        stopLockedProximityEnforcement()
        lockedProximitySessionID = session.id

        let stream = await touchTips.startLockedProximityMonitoring(roomID: session.id)
        lockedProximityUpdatesTask = Task { [weak self] in
            for await reading in stream {
                guard let self else { return }
                await self.recordLockedProximity(reading)
            }
        }

        lockedProximityCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: LockedSessionProximityPolicy.checkIntervalNanoseconds)
                guard let self else { return }
                await self.evaluateLockedProximity(sessionID: session.id)
            }
        }
    }

    private func stopLockedProximityEnforcement() {
        let shouldStopTouchTips = lockedProximitySessionID != nil
        lockedProximityUpdatesTask?.cancel()
        lockedProximityUpdatesTask = nil
        lockedProximityCheckTask?.cancel()
        lockedProximityCheckTask = nil
        proximityCountdownTask?.cancel()
        proximityCountdownTask = nil
        lockedProximitySessionID = nil
        latestLockedProximityReading = nil
        proximityWarningSecondsRemaining = nil
        if shouldStopTouchTips {
            Task { await touchTips.stop() }
        }
    }

    private func recordLockedProximity(_ reading: LockedProximityReading) {
        latestLockedProximityReading = reading
        if isWithinLockedProximityThreshold() {
            clearProximityWarning()
        }
    }

    private func evaluateLockedProximity(sessionID: UUID) async {
        guard phase == .locked, currentSession?.session.id == sessionID else { return }

        let reading = latestLockedProximityReading
        let distance = reading?.distanceMeters
        let stale = reading.map { Date().timeIntervalSince($0.observedAt) > LockedSessionProximityPolicy.staleReadingInterval } ?? true
        let withinThreshold = isWithinLockedProximityThreshold()
        if let d = distance {
            NSLog("[Unplugged][Proximity] 30s check — distance: %.2fm, threshold: %.2fm, within: %@, stale: %@, countdown active: %@",
                  d, LockedSessionProximityPolicy.maxDistanceMeters,
                  withinThreshold ? "YES" : "NO",
                  stale ? "YES" : "NO",
                  proximityCountdownTask != nil ? "YES" : "NO")
        } else {
            NSLog("[Unplugged][Proximity] 30s check — no distance reading (stale: %@, countdown active: %@)",
                  stale ? "YES" : "NO",
                  proximityCountdownTask != nil ? "YES" : "NO")
        }

        guard proximityCountdownTask == nil, !withinThreshold else { return }

        beginProximityWarningCountdown(sessionID: sessionID)
    }

    private func beginProximityWarningCountdown(sessionID: UUID) {
        proximityCountdownTask?.cancel()
        proximityWarningSecondsRemaining = LockedSessionProximityPolicy.gracePeriodSeconds
        proximityCountdownTask = Task { [weak self] in
            var remaining = LockedSessionProximityPolicy.gracePeriodSeconds
            while remaining > 0, !Task.isCancelled {
                guard let self else { return }
                if await self.isWithinLockedProximityThreshold() {
                    await self.clearProximityWarning()
                    return
                }

                try? await Task.sleep(nanoseconds: LockedSessionProximityPolicy.graceCheckIntervalNanoseconds)
                remaining -= 1
                await self.setProximityWarningSeconds(remaining)
            }

            guard !Task.isCancelled, let self else { return }
            if await self.isWithinLockedProximityThreshold() {
                await self.clearProximityWarning()
            } else {
                await self.reportProximityExit(sessionID: sessionID)
            }
        }
    }

    private func setProximityWarningSeconds(_ seconds: Int) {
        proximityWarningSecondsRemaining = max(seconds, 0)
    }

    private func clearProximityWarning() {
        proximityCountdownTask?.cancel()
        proximityCountdownTask = nil
        proximityWarningSecondsRemaining = nil
    }

    private func isWithinLockedProximityThreshold() -> Bool {
        guard let reading = latestLockedProximityReading,
              let distance = reading.distanceMeters,
              Date().timeIntervalSince(reading.observedAt) <= LockedSessionProximityPolicy.staleReadingInterval else {
            return false
        }
        return distance <= LockedSessionProximityPolicy.maxDistanceMeters
    }

    private func reportProximityExit(sessionID: UUID) async {
        guard !isReportingProximityExit else { return }
        isReportingProximityExit = true
        defer { isReportingProximityExit = false }

        do {
            try await sessions.reportProximityExit(id: sessionID)
            await completeLocalProximityExit()
        } catch {
            proximityWarningSecondsRemaining = nil
            proximityCountdownTask = nil
            errorMessage = "Couldn't leave the session after the proximity check."
        }
    }

    private func completeLocalProximityExit() async {
        stopJailbreakWatchdog()
        stopSessionSync()
        stopLockedProximityEnforcement()
        listenerTask?.cancel()
        listenerTask = nil
        await webSocket.disconnect()
        phase = .idle
        currentSession = nil
        participants = []
        countdownEndsAt = nil
        didLeaveCurrentSessionForProximity = true
    }

    private func resetShieldTracking() {
        lastShieldWarningSessionID = nil
        lastShieldWarningEndsAt = nil
        lastShieldWarningMessage = nil
        appliedShieldSessionID = nil
        appliedShieldEndsAt = nil
    }

    private func setShieldWarning(_ message: String, sessionID: UUID?, endsAt: Date) {
        guard !shieldMatches(sessionID: sessionID, endsAt: endsAt, trackedSessionID: lastShieldWarningSessionID, trackedEndsAt: lastShieldWarningEndsAt)
                || lastShieldWarningMessage != message else {
            return
        }
        lastShieldWarningSessionID = sessionID
        lastShieldWarningEndsAt = endsAt
        lastShieldWarningMessage = message
        errorMessage = message
    }

    private func shieldMatches(
        sessionID: UUID?,
        endsAt: Date,
        trackedSessionID: UUID?,
        trackedEndsAt: Date?
    ) -> Bool {
        guard trackedSessionID == sessionID, let trackedEndsAt else { return false }
        return abs(trackedEndsAt.timeIntervalSince(endsAt)) < 1
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

    private static func payloadUUID(from value: Any?) -> UUID? {
        if let uuid = value as? UUID {
            return uuid
        }
        if let string = value as? String {
            return UUID(uuidString: string)
        }
        return nil
    }

    private static func payloadDate(from value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }
        if let string = value as? String {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: string) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: string)
        }
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            let seconds = raw > 10_000_000_000 ? raw / 1_000 : raw
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }
}
