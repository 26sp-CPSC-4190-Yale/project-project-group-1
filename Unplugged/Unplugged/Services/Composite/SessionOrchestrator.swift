//
//  SessionOrchestrator.swift
//  UnpluggedServices.Composite
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Observation
import UnpluggedShared
#if canImport(AudioToolbox)
import AudioToolbox
#endif

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
    private var lockedProximityRecoveryTask: Task<Void, Never>?
    private var lockedProximitySessionID: UUID?
    private var latestLockedProximityReading: LockedProximityReading?
    private var lastLockedProximityAssessmentState: LockedProximityAssessment.State?
    private var lastLockedProximityRecoveryAt: Date?
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
        guard let session = currentSession else {
            AppLogger.session.warning("hostStart called with no currentSession")
            return
        }
        guard await ensureScreenTimePermissionForLockAttempt() else { return }
        do {
            let updated = try await sessions.startSession(id: session.session.id)
            await applySessionSnapshot(updated)
        } catch {
            AppLogger.session.error("hostStart failed", error: error, context: ["id": session.session.id.uuidString])
            errorMessage = "Couldn't start the session: \(error)"
        }
    }

    /// Host-only. Tells the server to end the room. Server broadcasts `sessionEnded`
    /// which will clear the shield and load the recap.
    func hostEnd() async {
        guard let session = currentSession else {
            AppLogger.session.warning("hostEnd called with no currentSession")
            return
        }
        do {
            _ = try await sessions.endSession(id: session.session.id)
        } catch {
            AppLogger.session.error("hostEnd failed", error: error, context: ["id": session.session.id.uuidString])
            errorMessage = "Couldn't end the session."
        }
    }

    /// Non-host. Voluntarily leave a session — drops the Screen Time shield
    /// locally, tells the server to mark the participant as left so the host
    /// (and other members) see them removed, and tears down the orchestrator
    /// so the device returns to idle. The shield is dropped even if the
    /// server call fails; otherwise a network blip would strand the user
    /// behind the lock with no way out short of waiting for the timer.
    func participantLeave() async {
        guard let session = currentSession else {
            AppLogger.session.warning("participantLeave called with no currentSession")
            return
        }
        let sessionID = session.session.id

        do {
            try await sessions.leaveSession(id: sessionID)
        } catch {
            AppLogger.session.error(
                "leaveSession failed — proceeding with local unlock anyway",
                error: error,
                context: ["id": sessionID.uuidString]
            )
        }

        do {
            try await screenTime.unlockApps()
        } catch {
            AppLogger.shield.critical(
                "unlockApps failed during participant leave — shield may be stuck",
                error: error,
                context: ["id": sessionID.uuidString]
            )
            errorMessage = "Couldn't unlock apps. Check Screen Time permission in Settings."
        }

        stopJailbreakWatchdog()
        stopSessionSync()
        stopLockedProximityEnforcement()
        listenerTask?.cancel()
        listenerTask = nil
        await webSocket.disconnect()
        await touchTips.stop()
        resetShieldTracking()

        phase = .idle
        currentSession = nil
        participants = []
        countdownEndsAt = nil
        lastRecap = nil
    }

    /// Called from `AppDelegate` when a silent APNs push arrives. Silent push is the
    /// fallback path when the WebSocket isn't connected (app suspended/killed).
    func applyRemoteLock(sessionID: UUID?, endsAt: Date) async {
        if let sessionID {
            startSessionSync(sessionID: sessionID)
            do {
                let response = try await sessions.getSession(id: sessionID)
                await applySessionSnapshot(response)
                return
            } catch {
                // Silent push woke us up but the backend fetch failed. We still
                // engage the shield below using the push-provided endsAt, but
                // the orchestrator state will be thinner than usual until the
                // next sync tick catches up.
                AppLogger.session.warning(
                    "applyRemoteLock: getSession failed, falling back to push-only lock",
                    context: ["id": sessionID.uuidString, "error": String(describing: error)]
                )
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
        await touchTips.stop()
        // §64: drop the Screen Time shield on teardown. If the user signs out
        // mid-session, leaving apps shielded with no session bound to them
        // strands the device — next launch shows a lock with no way to clear
        // it in-app. unlockApps is idempotent when nothing is shielded.
        do {
            try await screenTime.unlockApps()
        } catch {
            // Shield leak on teardown. Not user-recoverable in-app — they'd
            // need to yank the Screen Time permission. Critical because the
            // user is now stranded.
            AppLogger.shield.critical("unlockApps failed during teardown — shield may be stuck", error: error)
        }
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
        guard let token = cache.readCachedToken() else {
            // No cached token => no auth => session will fall back to polling.
            // This tends to happen when a silent push beats the keychain
            // prewarm; the next `didBecomeActive` sync loop picks it up.
            AppLogger.session.warning("connectWebSocket skipped: no cached token", context: ["id": sessionID.uuidString])
            return
        }
        listenerTask?.cancel()
        let stream = await webSocket.connect(sessionID: sessionID, token: token)
        AppLogger.breadcrumb(.session, "ws_listener_started", context: ["id": sessionID.uuidString])
        listenerTask = Task { [weak self] in
            for await message in stream {
                guard let self else { return }
                await self.handle(message: message)
            }
            AppLogger.session.warning("ws listener loop ended — stream closed", context: ["id": sessionID.uuidString])
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
            // The WebSocket remains the primary real-time path; transient
            // polling failures are expected. Log as warning (not error) so
            // they're visible in trace but don't look like bugs. Repeated
            // failures here == we're drifting from server truth.
            AppLogger.session.warning(
                "session reconcile poll failed",
                context: ["id": sessionID.uuidString, "error": String(describing: error)]
            )
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
                AppLogger.session.critical(
                    "session locked but endsAt missing — server protocol violation",
                    context: ["id": response.session.id.uuidString]
                )
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

        guard await ensureScreenTimePermissionForLockAttempt(sessionID: sessionID, endsAt: endsAt) else {
            return
        }

        do {
            try await screenTime.lockApps(endsAt: endsAt)
            appliedShieldSessionID = sessionID
            appliedShieldEndsAt = endsAt
            lastShieldWarningSessionID = nil
            lastShieldWarningEndsAt = nil
            lastShieldWarningMessage = nil
            startJailbreakWatchdog()
        } catch {
            // Shield engagement is the whole point of the app — a failure here
            // means the session is effectively cosmetic. `critical` level so
            // it lights up in log search.
            AppLogger.shield.critical(
                "lockApps failed",
                error: error,
                context: [
                    "session": sessionID?.uuidString ?? "<none>",
                    "endsAt": ISO8601DateFormatter().string(from: endsAt)
                ]
            )
            AppLogger.dumpRecent("shield", limit: 30)
            setShieldWarning("Couldn't engage the shield. Check Screen Time permission in Settings and try again.", sessionID: sessionID, endsAt: endsAt)
        }
    }

    private func ensureScreenTimePermissionForLockAttempt(
        sessionID: UUID? = nil,
        endsAt: Date? = nil
    ) async -> Bool {
        guard screenTime.isAvailable else {
            if let endsAt {
                setShieldWarning("Screen Time is unavailable on this device, so apps can't be blocked.", sessionID: sessionID, endsAt: endsAt)
            } else {
                errorMessage = "Screen Time is unavailable on this device, so apps can't be blocked."
            }
            return false
        }

        if screenTime.isAuthorized {
            return true
        }

        do {
            try await screenTime.requestAuthorization()
        } catch {
            // Fall through to the final status check. FamilyControls can lag when
            // returning from Settings or the permission sheet, so the property is
            // still the source of truth after a short revalidation attempt.
            AppLogger.shield.warning(
                "requestAuthorization threw — relying on status poll to resolve",
                context: ["error": String(describing: error)]
            )
        }

        if screenTime.isAuthorized {
            return true
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        guard screenTime.isAuthorized else {
            let message = "Screen Time permission is required before Unplugged can lock apps."
            if let endsAt {
                setShieldWarning(message, sessionID: sessionID, endsAt: endsAt)
            } else {
                errorMessage = message
            }
            return false
        }

        return true
    }

    private func handleSessionEnded() async {
        stopJailbreakWatchdog()
        stopSessionSync()
        stopLockedProximityEnforcement()
        do {
            try await screenTime.unlockApps()
        } catch {
            AppLogger.shield.critical(
                "unlockApps failed on session end — shield may be stuck",
                error: error
            )
        }
        await touchTips.stop()
        resetShieldTracking()
        self.phase = .ended
        if let id = currentSession?.session.id {
            do {
                self.lastRecap = try await recap.getRecap(sessionID: id)
            } catch {
                // Recap may not be available immediately; the recap screen
                // will retry. Warning-level because repeated failures here
                // mean the user never gets their recap.
                AppLogger.session.warning(
                    "recap fetch failed on session end",
                    context: ["id": id.uuidString, "error": String(describing: error)]
                )
            }
        }
        listenerTask?.cancel()
        listenerTask = nil
        await webSocket.disconnect()
    }

    // MARK: - Locked-room proximity enforcement

    private struct LockedProximityAssessment: Sendable {
        enum State: String, Sendable {
            case noReading
            case stale
            case missingDistance
            case withinThreshold
            case outOfRange
        }

        let state: State
        let distanceMeters: Double?
        let age: TimeInterval?
        let reason: String?

        var isWithinThreshold: Bool {
            state == .withinThreshold
        }

        var isFreshOutOfRange: Bool {
            state == .outOfRange
        }

        var needsSignalRecovery: Bool {
            switch state {
            case .noReading, .missingDistance:
                return true
            case .stale:
                return (age ?? 0) >= LockedSessionProximityPolicy.staleRecoveryInterval
            case .withinThreshold, .outOfRange:
                return false
            }
        }

        var recoveryReason: String {
            switch state {
            case .noReading:
                return "no_reading"
            case .stale:
                return "stale_\(reason ?? "unknown")"
            case .missingDistance:
                return "missing_\(reason ?? "unknown")"
            case .withinThreshold:
                return "within_threshold"
            case .outOfRange:
                return "out_of_range"
            }
        }

        var logDescription: String {
            let distanceText = distanceMeters.map { String(format: "%.2fm", $0) } ?? "nil"
            let ageText = age.map { String(format: "%.1fs", $0) } ?? "nil"
            return "state: \(state.rawValue), distance: \(distanceText), threshold: \(String(format: "%.2fm", LockedSessionProximityPolicy.maxDistanceMeters)), age: \(ageText), reason: \(reason ?? "none")"
        }
    }

    private func startLockedProximityEnforcementIfNeeded() async {
        guard phase == .locked,
              let session = currentSession?.session,
              lockedProximitySessionID != session.id else {
            AppLogger.proximity.info("enforcement start skipped — phase=\(phase) hasSession=\(currentSession?.session != nil) alreadyMonitoring=\(lockedProximitySessionID != nil)")
            return
        }

        guard let userID = cache.readUser()?.id else {
            AppLogger.proximity.warning("enforcement start skipped — no cached user")
            stopLockedProximityEnforcement()
            return
        }
        guard userID != session.hostID else {
            AppLogger.proximity.info("enforcement start skipped — user IS host", context: ["userID": userID.uuidString, "hostID": session.hostID.uuidString])
            stopLockedProximityEnforcement()
            return
        }

        guard await touchTips.supportsLockedProximityMonitoring() else {
            AppLogger.proximity.warning("enforcement start skipped — UWB not supported on device")
            stopLockedProximityEnforcement()
            return
        }
        AppLogger.proximity.info("enforcement starting for session \(session.id.uuidString)")

        stopLockedProximityEnforcement()
        lockedProximitySessionID = session.id

        await installLockedProximityStream(sessionID: session.id, reason: "initial_start")

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
        lockedProximityRecoveryTask?.cancel()
        lockedProximityRecoveryTask = nil
        lockedProximitySessionID = nil
        latestLockedProximityReading = nil
        lastLockedProximityAssessmentState = nil
        lastLockedProximityRecoveryAt = nil
        proximityWarningSecondsRemaining = nil
        if shouldStopTouchTips {
            Task { await touchTips.stop() }
        }
    }

    private func installLockedProximityStream(sessionID: UUID, reason: String) async {
        AppLogger.proximity.info("stream install — session=\(sessionID.uuidString) reason=\(reason)")
        let stream = await touchTips.startLockedProximityMonitoring(roomID: sessionID)
        lockedProximityUpdatesTask = Task { [weak self] in
            for await reading in stream {
                guard let self else { return }
                await self.recordLockedProximity(reading)
            }
            guard !Task.isCancelled, let self else { return }
            await self.handleLockedProximityStreamEnded(sessionID: sessionID)
        }
    }

    private func handleLockedProximityStreamEnded(sessionID: UUID) {
        guard phase == .locked, currentSession?.session.id == sessionID else { return }
        AppLogger.proximity.warning("stream ended unexpectedly — requesting recovery", context: ["session": sessionID.uuidString])
        requestLockedProximityRecovery(sessionID: sessionID, reason: "stream_ended")
    }

    private func recordLockedProximity(_ reading: LockedProximityReading) {
        latestLockedProximityReading = reading
        let assessment = lockedProximityAssessment()
        let stateChanged = lastLockedProximityAssessmentState != assessment.state
        lastLockedProximityAssessmentState = assessment.state
        if assessment.isWithinThreshold {
            if proximityCountdownTask != nil || stateChanged {
                AppLogger.proximity.info("distance recovered — \(assessment.logDescription)")
            }
            clearProximityWarning()
        } else if assessment.isFreshOutOfRange {
            if let sessionID = lockedProximitySessionID,
               proximityCountdownTask == nil {
                beginProximityWarningCountdown(sessionID: sessionID, initialAssessment: assessment)
            }
        } else if reading.distanceMeters == nil, stateChanged {
            AppLogger.proximity.warning("no-distance reading recorded — \(assessment.logDescription)")
        }
    }

    private func evaluateLockedProximity(sessionID: UUID) async {
        guard phase == .locked, currentSession?.session.id == sessionID else { return }

        let assessment = lockedProximityAssessment()
        AppLogger.proximity.debug("30s check — \(assessment.logDescription), countdown active: \(proximityCountdownTask != nil)")

        if assessment.isWithinThreshold {
            clearProximityWarning()
            return
        }

        if assessment.needsSignalRecovery {
            if proximityCountdownTask != nil {
                AppLogger.proximity.warning("clearing proximity warning because signal is unavailable — \(assessment.logDescription)")
                clearProximityWarning()
            }
            requestLockedProximityRecovery(sessionID: sessionID, reason: assessment.recoveryReason)
            return
        }

        guard proximityCountdownTask == nil, assessment.isFreshOutOfRange else { return }

        beginProximityWarningCountdown(sessionID: sessionID, initialAssessment: assessment)
    }

    private func beginProximityWarningCountdown(sessionID: UUID, initialAssessment: LockedProximityAssessment) {
        proximityCountdownTask?.cancel()
        proximityWarningSecondsRemaining = LockedSessionProximityPolicy.gracePeriodSeconds
        AppLogger.proximity.warning("starting leave countdown — \(initialAssessment.logDescription)")
        proximityCountdownTask = Task { [weak self] in
            var remaining = LockedSessionProximityPolicy.gracePeriodSeconds
            while remaining > 0, !Task.isCancelled {
                guard let self else { return }
                let assessment = await self.lockedProximityAssessment()
                if assessment.isWithinThreshold {
                    AppLogger.proximity.info("leave countdown cancelled: back within range — \(assessment.logDescription)")
                    await self.clearProximityWarning()
                    return
                }
                if assessment.needsSignalRecovery {
                    AppLogger.proximity.warning("leave countdown paused: signal unavailable — \(assessment.logDescription)")
                    await self.clearProximityWarning()
                    await self.requestLockedProximityRecovery(sessionID: sessionID, reason: assessment.recoveryReason)
                    return
                }

                #if canImport(AudioToolbox)
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                #endif

                try? await Task.sleep(nanoseconds: LockedSessionProximityPolicy.graceCheckIntervalNanoseconds)
                remaining -= 1
                await self.setProximityWarningSeconds(remaining)
            }

            guard !Task.isCancelled, let self else { return }
            let finalAssessment = await self.lockedProximityAssessment()
            if finalAssessment.isWithinThreshold {
                AppLogger.proximity.info("leave countdown finished but device is within range — \(finalAssessment.logDescription)")
                await self.clearProximityWarning()
            } else if finalAssessment.isFreshOutOfRange {
                AppLogger.proximity.warning("leave countdown finished with fresh out-of-range distance — \(finalAssessment.logDescription)")
                await self.reportProximityExit(sessionID: sessionID)
            } else {
                AppLogger.proximity.warning("leave countdown finished without fresh distance; NOT reporting exit — \(finalAssessment.logDescription)")
                await self.clearProximityWarning()
                await self.requestLockedProximityRecovery(sessionID: sessionID, reason: finalAssessment.recoveryReason)
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
        lockedProximityAssessment().isWithinThreshold
    }

    private func lockedProximityAssessment(now: Date = Date()) -> LockedProximityAssessment {
        guard let reading = latestLockedProximityReading else {
            return LockedProximityAssessment(
                state: .noReading,
                distanceMeters: nil,
                age: nil,
                reason: "no_reading_recorded"
            )
        }

        let age = now.timeIntervalSince(reading.observedAt)
        if age > LockedSessionProximityPolicy.staleReadingInterval {
            return LockedProximityAssessment(
                state: .stale,
                distanceMeters: reading.distanceMeters,
                age: age,
                reason: reading.reason ?? "reading_stale"
            )
        }

        guard let distance = reading.distanceMeters else {
            return LockedProximityAssessment(
                state: .missingDistance,
                distanceMeters: nil,
                age: age,
                reason: reading.reason ?? "distance_missing"
            )
        }

        return LockedProximityAssessment(
            state: distance <= LockedSessionProximityPolicy.maxDistanceMeters ? .withinThreshold : .outOfRange,
            distanceMeters: distance,
            age: age,
            reason: reading.reason
        )
    }

    private func requestLockedProximityRecovery(sessionID: UUID, reason: String) {
        guard phase == .locked, currentSession?.session.id == sessionID else { return }
        if lockedProximityRecoveryTask != nil {
            AppLogger.proximity.debug("recovery already in flight — reason=\(reason)")
            return
        }
        if let lastLockedProximityRecoveryAt,
           Date().timeIntervalSince(lastLockedProximityRecoveryAt) < LockedSessionProximityPolicy.recoveryCooldown {
            AppLogger.proximity.debug("recovery throttled — reason=\(reason)")
            return
        }

        lastLockedProximityRecoveryAt = Date()
        lockedProximityRecoveryTask = Task { [weak self] in
            guard let self else { return }
            await self.performLockedProximityRecovery(sessionID: sessionID, reason: reason)
        }
    }

    private func performLockedProximityRecovery(sessionID: UUID, reason: String) async {
        defer { lockedProximityRecoveryTask = nil }
        guard phase == .locked, currentSession?.session.id == sessionID else { return }
        AppLogger.proximity.warning("recovery starting — session=\(sessionID.uuidString) reason=\(reason)")

        lockedProximityUpdatesTask?.cancel()
        lockedProximityUpdatesTask = nil
        latestLockedProximityReading = nil
        lastLockedProximityAssessmentState = nil
        await touchTips.stop()

        guard !Task.isCancelled,
              phase == .locked,
              currentSession?.session.id == sessionID else { return }

        guard await touchTips.supportsLockedProximityMonitoring() else {
            AppLogger.proximity.warning("recovery stopped — UWB not supported")
            return
        }

        lockedProximitySessionID = sessionID
        await installLockedProximityStream(sessionID: sessionID, reason: "recovery_\(reason)")
        AppLogger.proximity.info("recovery completed — session=\(sessionID.uuidString)")
    }

    private func reportProximityExit(sessionID: UUID) async {
        guard !isReportingProximityExit else { return }
        let assessment = lockedProximityAssessment()
        guard assessment.isFreshOutOfRange else {
            AppLogger.proximity.warning("blocked proximity exit report without fresh out-of-range distance — \(assessment.logDescription)")
            clearProximityWarning()
            if assessment.needsSignalRecovery {
                requestLockedProximityRecovery(sessionID: sessionID, reason: assessment.recoveryReason)
            }
            return
        }

        isReportingProximityExit = true
        defer { isReportingProximityExit = false }

        do {
            try await sessions.reportProximityExit(id: sessionID)
            await completeLocalProximityExit()
        } catch {
            AppLogger.proximity.error(
                "reportProximityExit failed — user still marked active on server",
                error: error,
                context: ["session": sessionID.uuidString]
            )
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
        guard let sessionID = currentSession?.session.id else {
            AppLogger.shield.warning("startJailbreakWatchdog: no session to watch")
            return
        }
        jailbreakWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self else { return }
                if !(await self.isShieldStillAuthorized()) {
                    AppLogger.shield.critical(
                        "jailbreak detected — Screen Time permission cleared mid-session",
                        context: ["session": sessionID.uuidString]
                    )
                    do {
                        try await self.sessions.reportJailbreak(id: sessionID, reason: "screen_time_auth_cleared")
                    } catch {
                        AppLogger.shield.error("jailbreak REST report failed", error: error, context: ["session": sessionID.uuidString])
                    }
                    do {
                        try await self.webSocket.send(.reportJailbreak(reason: "screen_time_auth_cleared"))
                    } catch {
                        AppLogger.shield.error("jailbreak WS report failed", error: error, context: ["session": sessionID.uuidString])
                    }
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
