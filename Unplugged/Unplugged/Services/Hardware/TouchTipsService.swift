//
//  TouchTipsService.swift
//  Unplugged.Services.Hardware
//
//  Proximity-based room pairing built on MultipeerConnectivity (discovery + messaging)
//  and NearbyInteraction (short-range UWB distance gating).
//
//  Why not GroupActivities / SharePlay?
//  GroupActivities is designed for FaceTime-relayed shared sessions, not on-device
//  proximity pairing. iOS 17+ also intercepts "tips-together" gestures as NameDrop,
//  which third-party apps cannot override. The previous implementation used
//  GroupActivities in a way that Apple's TipKit never actually fired locally, so
//  discovery never worked and users got NameDrop instead.
//
//  Flow
//  ────
//    1. Host calls `activate(roomID:)`. TouchTipsService starts advertising on
//       `unplugged-rm` with the room UUID in the discoveryInfo dict.
//    2. Joiner calls `startListening()`, gets an AsyncStream back. Browser starts,
//       auto-invites any advertiser it sees on the same service type (no UI).
//    3. MCSession connects. Host sends a one-shot handshake:
//         { "roomID": "<uuid>", "niToken": "<base64-archived NIDiscoveryToken>" }
//    4. Both sides start an NISession configured with the peer's token and begin
//       receiving distance readings.
//    5. When distance <= ProximityConstants.touchThresholdMeters (10 cm) for
//       `consecutiveCloseSamples` (2) consecutive readings, the joiner yields the
//       room UUID on its AsyncStream and auto-joins — no buttons.
//
//  No MC-only fallback for auto-pairing
//  ────────────────────────────────────
//  MC alone is ~10 m range (BT LE + P2P Wi-Fi). Auto-pairing on MC connect would let
//  two phones in the same room silently pair — exactly the bug we've seen. UWB is the
//  ONLY auto-pair gate. If UWB is unavailable (pre-U1 hardware, permission denied,
//  older iOS) the stream simply never yields; the UI surfaces the manual room-code
//  path instead. Do not reintroduce a time-based "if MC connects, assume proximity"
//  shortcut — users will join from across the room.
//

import Foundation
import MultipeerConnectivity
import NearbyInteraction
import Network
import UnpluggedShared
#if canImport(UIKit)
import UIKit
#endif

actor TouchTipsService {

    // MARK: - Public API

    /// Host: advertise this roomID so nearby joiners can auto-pair.
    func activate(roomID: UUID) async throws {
        stopInternal(keepContinuation: true)
        role = .host(roomID: roomID)

        let peerID = MCPeerID(displayName: "unplugged-\(UUID().uuidString.prefix(6))")
        localPeerID = peerID
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = bridge
        mcSession = session

        let info = ["roomID": roomID.uuidString, "v": "1"]
        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: info,
            serviceType: ProximityConstants.serviceType
        )
        advertiser.delegate = bridge
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()
    }

    /// Joiner: return a stream that yields the host's roomID when phones are close.
    /// Re-entrant: a second call finishes the previous stream and starts over.
    func startListening() -> AsyncStream<UUID> {
        stopInternal(keepContinuation: false)
        role = .joiner
        didYield = false

        let stream = AsyncStream<UUID> { cont in
            self.continuation = cont
        }

        let peerID = MCPeerID(displayName: "unplugged-\(UUID().uuidString.prefix(6))")
        localPeerID = peerID
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = bridge
        mcSession = session

        let browser = MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: ProximityConstants.serviceType
        )
        browser.delegate = bridge
        self.browser = browser
        browser.startBrowsingForPeers()

        return stream
    }

    func startLockedProximityMonitoring(roomID: UUID) -> AsyncStream<LockedProximityReading> {
        stopInternal(keepContinuation: false)
        role = .lockedGuest(roomID: roomID)
        log("locked monitor starting for room \(roomID.uuidString)")

        let stream = AsyncStream<LockedProximityReading> { cont in
            self.lockedProximityContinuation = cont
        }

        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            log("locked monitor cannot start: precise distance unsupported")
            emitLockedProximity(distanceMeters: nil, reason: "uwb_unsupported")
            return stream
        }

        let peerID = MCPeerID(displayName: "unplugged-\(UUID().uuidString.prefix(6))")
        localPeerID = peerID
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = bridge
        mcSession = session

        let browser = MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: ProximityConstants.serviceType
        )
        browser.delegate = bridge
        self.browser = browser
        browser.startBrowsingForPeers()

        log("locked monitor browsing for room \(roomID.uuidString) as \(peerID.displayName)")
        emitLockedProximity(distanceMeters: nil, reason: "monitor_started")
        return stream
    }

    func supportsLockedProximityMonitoring() -> Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    func stop() {
        stopInternal(keepContinuation: false)
    }

    /// Trigger the OS Local Network permission dialog during onboarding so the first
    /// real pairing attempt doesn't silently fail. The Bonjour browser resolves only
    /// after iOS has accepted or denied local-network access, which lets onboarding
    /// wait for the user's actual choice before moving forward.
    func primeLocalNetworkPermission() async -> Bool {
        stopInternal(keepContinuation: false)

        return await Self.requestLocalNetworkPermission()
    }

    // MARK: - Init (wire up delegate bridge)

    init() {
        let bridge = ProximityBridge()
        self.bridge = bridge
        // P1-9: wire the delegate bridge synchronously in init. The previous
        // `Task { await self.wireBridge() }` pattern left a window where early
        // MC/NI callbacks would fire with nil closures on the bridge and be
        // silently dropped. All the closures do here is spawn a `Task` to hand
        // the event off to the actor, which is safe from any sync context.
        //
        // The closures capture `[weak self]` so the bridge does not extend the
        // actor's lifetime; if the actor dies, in-flight events become no-ops.
        // Every mutation of `peerDiscoveryTokens`, `niSessions`, etc. happens
        // inside actor-isolated methods after the Task suspension, so there is
        // no cross-queue access to the shared dictionaries.
        bridge.onFoundPeer = { [weak self] peer, info in
            Task { await self?.handleFoundPeer(peer: peer, info: info) }
        }
        bridge.onInvitation = { [weak self] peer, invitationHandler in
            Task { await self?.handleInvitation(peer: peer, handler: invitationHandler) }
        }
        bridge.onSessionState = { [weak self] peer, state in
            Task { await self?.handleSessionState(peer: peer, state: state) }
        }
        bridge.onDataReceived = { [weak self] peer, data in
            Task { await self?.handleDataReceived(peer: peer, data: data) }
        }
        bridge.onNIUpdate = { [weak self] objects in
            Task { await self?.handleNIUpdate(objects: objects) }
        }
        bridge.onNIRemoved = { [weak self] _ in
            // Peer moved out of range or session broke. Not fatal — keep MC alive so
            // they can approach again without re-pairing.
            Task { await self?.handleNIRemoved() }
        }
        bridge.onNIInvalidated = { [weak self] error in
            Task { await self?.resetNI(reason: String(describing: error)) }
        }
        bridge.onLostPeer = { [weak self] peer in
            Task { await self?.handleLostPeer(peer: peer) }
        }
        bridge.onBrowserFailure = { [weak self] error in
            Task { await self?.handleBrowserFailure(error) }
        }
        bridge.onAdvertiserFailure = { [weak self] error in
            Task { await self?.handleAdvertiserFailure(error) }
        }
        bridge.onNISuspended = { [weak self] in
            Task { await self?.handleNISuspended() }
        }
        bridge.onNISuspensionEnded = { [weak self] in
            Task { await self?.handleNISuspensionEnded() }
        }
    }

    // MARK: - Internal state

    private enum Role {
        case none
        case host(roomID: UUID)
        case joiner
        case lockedGuest(roomID: UUID)
    }

    private var role: Role = .none
    private var continuation: AsyncStream<UUID>.Continuation?
    private var lockedProximityContinuation: AsyncStream<LockedProximityReading>.Continuation?

    private let bridge: ProximityBridge
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var mcSession: MCSession?
    private var localPeerID: MCPeerID?

    /// roomID pulled from discoveryInfo on the joiner side, keyed by the peer we invited.
    /// Used as a fallback if the handshake message arrives before we've parsed the payload,
    /// or if the host never sends a roomID for some reason.
    private var discoveredRoomID: [MCPeerID: UUID] = [:]

    private var niSessions: [MCPeerID: NISession] = [:]
    private var peerDiscoveryTokens: [MCPeerID: NIDiscoveryToken] = [:]
    private var didYield = false

    /// Count of consecutive sub-threshold distance samples. Reset whenever a reading
    /// comes back above the threshold (or is missing). We require N in a row — a single
    /// spike below 10cm during a hand wave isn't proof the phones are together.
    private var consecutiveCloseCount: Int = 0

    // MARK: - MC event handlers

    private func handleFoundPeer(peer: MCPeerID, info: [String: String]?) {
        guard let session = mcSession,
              let browser = browser else {
            log("found peer \(peer.displayName) ignored: missing MC session/browser")
            return
        }

        if let uuidString = info?["roomID"], let roomID = UUID(uuidString: uuidString) {
            discoveredRoomID[peer] = roomID
        }

        switch role {
        case .joiner:
            log("joiner found peer \(peer.displayName), info room \(info?["roomID"] ?? "nil")")
            break
        case .lockedGuest(let roomID):
            guard discoveredRoomID[peer] == roomID else {
                log("locked monitor ignoring peer \(peer.displayName): expected room \(roomID.uuidString), discovered \(discoveredRoomID[peer]?.uuidString ?? "nil")")
                return
            }
            log("locked monitor found matching host peer \(peer.displayName) for room \(roomID.uuidString)")
        case .none, .host:
            log("found peer \(peer.displayName) ignored for role \(roleLogDescription)")
            return
        }

        log("inviting peer \(peer.displayName) for role \(roleLogDescription)")
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 15)
    }

    private func handleInvitation(peer: MCPeerID, handler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept any inbound invite on our namespaced service — the service type
        // itself is the coarse gate; UWB is the fine gate.
        log("received invitation from \(peer.displayName), accepting: \(mcSession != nil ? "YES" : "NO_SESSION")")
        handler(true, mcSession)
    }

    private func handleSessionState(peer: MCPeerID, state: MCSessionState) {
        log("MC session state for \(peer.displayName): \(state.logDescription) role: \(roleLogDescription)")
        if state == .connected {
            sendHandshake(to: peer)
        } else {
            niSessions[peer]?.invalidate()
            niSessions[peer] = nil
            peerDiscoveryTokens[peer] = nil
            if case .lockedGuest = role {
                emitLockedProximity(distanceMeters: nil, reason: "mc_\(state.logDescription)")
            }
        }
        // Do NOT schedule an MC-only yield here — MC connecting only proves radio
        // proximity (~10 m). The UWB gate in handleNIUpdate is what confirms the
        // phones are actually pressed together.
    }

    private func sendHandshake(to peer: MCPeerID) {
        guard let session = mcSession else { return }

        let ni = makeNISession(for: peer)

        var payload: [String: String] = [:]
        if case .host(let roomID) = role {
            payload["roomID"] = roomID.uuidString
        }
        if let token = ni?.discoveryToken,
           let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            payload["niToken"] = tokenData.base64EncodedString()
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            AppLogger.touchTips.error("handshake encode failed", error: error, context: ["peer": peer.displayName])
            return
        }
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
            log("handshake sent to \(peer.displayName): roomID=\(payload["roomID"] != nil ? "YES" : "NO"), niToken=\(payload["niToken"] != nil ? "YES" : "NO")")
        } catch {
            AppLogger.touchTips.error("handshake send failed", error: error, context: ["peer": peer.displayName])
            if case .lockedGuest = role {
                emitLockedProximity(distanceMeters: nil, reason: "handshake_send_failed")
            }
        }
    }

    private func handleDataReceived(peer: MCPeerID, data: Data) {
        let payload: [String: String]
        do {
            payload = try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            AppLogger.touchTips.error("inbound data decode failed", error: error, context: ["peer": peer.displayName, "bytes": data.count])
            return
        }
        log("data received from \(peer.displayName): roomID=\(payload["roomID"] != nil ? "YES" : "NO"), niToken=\(payload["niToken"] != nil ? "YES" : "NO")")

        // Capture host's roomID if we didn't already have it from discoveryInfo.
        if (isJoiner || isLockedGuest),
           let uuidString = payload["roomID"],
           let roomID = UUID(uuidString: uuidString) {
            discoveredRoomID[peer] = roomID
        }

        if case .lockedGuest(let expectedRoomID) = role,
           let roomID = discoveredRoomID[peer],
           roomID != expectedRoomID {
            log("locked monitor ignoring data from \(peer.displayName): expected room \(expectedRoomID.uuidString), got \(roomID.uuidString)")
            return
        }

        // Extract NI discovery token and start the NI session against it.
        guard let tokenB64 = payload["niToken"],
              let tokenData = Data(base64Encoded: tokenB64),
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: tokenData) else {
            log("NI token missing/invalid from \(peer.displayName)")
            if case .lockedGuest = role {
                emitLockedProximity(distanceMeters: nil, reason: "ni_token_missing")
            }
            return
        }
        peerDiscoveryTokens[peer] = token
        startNIRanging(with: token, peer: peer)
    }

    private func startNIRanging(with token: NIDiscoveryToken, peer: MCPeerID) {
        guard let ni = makeNISession(for: peer) else {
            log("NI ranging skipped for \(peer.displayName): precise distance unsupported")
            if case .lockedGuest = role {
                emitLockedProximity(distanceMeters: nil, reason: "uwb_unsupported")
            }
            return
        }
        let config = NINearbyPeerConfiguration(peerToken: token)
        ni.run(config)
        log("NI ranging started for \(peer.displayName)")
    }

    // MARK: - NI event handler

    private func handleNIUpdate(objects: [NINearbyObject]) {
        let match = objects.compactMap { object -> Float? in
            guard let distance = object.distance else { return nil }
            return peerDiscoveryTokens.values.contains { $0 == object.discoveryToken } ? distance : nil
        }.first

        guard let distance = match else {
            // Token didn't match any of the nearby objects (peer disappeared, or the
            // update is for a stale session). Don't penalize the counter — wait for the
            // next real sample. But DO decay it back to 0 so momentary losses don't
            // bank progress toward the gate.
            consecutiveCloseCount = 0
            if case .lockedGuest = role {
                emitLockedProximity(distanceMeters: nil, reason: "ni_update_without_distance")
            }
            return
        }

        if case .lockedGuest = role {
            emitLockedProximity(distanceMeters: Double(distance))
            return
        }

        guard !didYield else { return }

        if distance <= Float(ProximityConstants.touchThresholdMeters) {
            consecutiveCloseCount += 1
            if consecutiveCloseCount >= ProximityConstants.consecutiveCloseSamples {
                yieldIfStillWaiting(reason: "UWB <=\(ProximityConstants.touchThresholdMeters)m x\(consecutiveCloseCount)")
            }
        } else {
            // Any reading above the threshold resets the streak. The user must hold
            // the phones together long enough for two clean samples in a row.
            consecutiveCloseCount = 0
        }
    }

    private func handleNIRemoved() {
        consecutiveCloseCount = 0
        if case .lockedGuest = role {
            log("NI peer removed while locked monitor active")
            emitLockedProximity(distanceMeters: nil, reason: "ni_peer_removed")
        }
    }

    private func resetNI(reason: String) {
        log("NI reset for role \(roleLogDescription), reason: \(reason)")
        for session in niSessions.values {
            session.invalidate()
        }
        niSessions.removeAll()
        peerDiscoveryTokens.removeAll()
        consecutiveCloseCount = 0
        if case .lockedGuest = role {
            emitLockedProximity(distanceMeters: nil, reason: "ni_invalidated")
        }
    }

    private func handleLostPeer(peer: MCPeerID) {
        log("lost peer \(peer.displayName) for role \(roleLogDescription)")
        niSessions[peer]?.invalidate()
        niSessions[peer] = nil
        peerDiscoveryTokens[peer] = nil
        if case .lockedGuest = role {
            emitLockedProximity(distanceMeters: nil, reason: "mc_lost_peer")
        }
    }

    private func handleBrowserFailure(_ error: Error) {
        AppLogger.touchTips.error("MC browser failed", error: error, context: ["role": roleLogDescription])
        if case .lockedGuest = role {
            emitLockedProximity(distanceMeters: nil, reason: "browser_failed")
        }
    }

    private func handleAdvertiserFailure(_ error: Error) {
        AppLogger.touchTips.error("MC advertiser failed", error: error, context: ["role": roleLogDescription])
    }

    private func handleNISuspended() {
        log("NI suspended for role \(roleLogDescription)")
        if case .lockedGuest = role {
            emitLockedProximity(distanceMeters: nil, reason: "ni_suspended")
        }
    }

    private func handleNISuspensionEnded() {
        log("NI suspension ended for role \(roleLogDescription)")
    }

    // MARK: - Yielding

    private func yieldIfStillWaiting(reason: String) {
        guard !didYield, case .joiner = role, let continuation else { return }
        // Pick any room we've learned about. In practice there's only one peer at a time.
        guard let roomID = discoveredRoomID.values.first else { return }
        didYield = true
        continuation.yield(roomID)
    }

    private var isJoiner: Bool {
        if case .joiner = role { return true }
        return false
    }

    private var isLockedGuest: Bool {
        if case .lockedGuest = role { return true }
        return false
    }

    private func makeNISession(for peer: MCPeerID) -> NISession? {
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else { return nil }
        if let existing = niSessions[peer] {
            return existing
        }
        let ni = NISession()
        ni.delegate = bridge
        niSessions[peer] = ni
        log("NI session created for \(peer.displayName)")
        return ni
    }

    private func emitLockedProximity(distanceMeters: Double?, reason: String? = nil) {
        if distanceMeters == nil {
            log("locked monitor emitted no-distance reading, reason: \(reason ?? "unknown")")
        }
        lockedProximityContinuation?.yield(
            LockedProximityReading(distanceMeters: distanceMeters, observedAt: Date(), reason: reason)
        )
    }

    private var roleLogDescription: String {
        switch role {
        case .none:
            return "none"
        case .host(let roomID):
            return "host(\(roomID.uuidString))"
        case .joiner:
            return "joiner"
        case .lockedGuest(let roomID):
            return "lockedGuest(\(roomID.uuidString))"
        }
    }

    /// Routes through AppLogger.touchTips so the kill switch silences the
    /// chatty proximity pairing trace. Level is `.info` — individual failure
    /// sites use `.warning` / `.error` directly where they matter.
    private func log(_ message: String) {
        AppLogger.touchTips.info(message)
    }

    // MARK: - Teardown

    private func stopInternal(keepContinuation: Bool) {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil

        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil

        mcSession?.disconnect()
        mcSession?.delegate = nil
        mcSession = nil

        for session in niSessions.values {
            session.invalidate()
        }
        niSessions.removeAll()
        peerDiscoveryTokens.removeAll()
        consecutiveCloseCount = 0

        localPeerID = nil
        discoveredRoomID.removeAll()
        role = .none

        if !keepContinuation {
            continuation?.finish()
            continuation = nil
            lockedProximityContinuation?.finish()
            lockedProximityContinuation = nil
            didYield = false
        }
    }
}

private extension TouchTipsService {
    static func requestLocalNetworkPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            let resolver = LocalNetworkPermissionResolver(continuation: continuation)
            resolver.start()
        }
    }
}

/// Drives the iOS Local Network permission prompt and resolves once the user
/// has actually responded.
///
/// `NWBrowser.State.ready` only means the browser started. It can arrive before
/// the Local Network alert is answered, so treating it as approval makes
/// onboarding advance while the system alert is still visible.
///
/// To verify a real approval, this publishes a short-lived Bonjour probe and
/// browses for that exact service. Seeing the probe means Bonjour traffic was
/// allowed. Policy-denied browser/listener states are held until the prompt is
/// dismissed, because they can also arrive while the alert is still pending.
private final class LocalNetworkPermissionResolver: @unchecked Sendable {
    private let continuation: CheckedContinuation<Bool, Never>
    private let queue = DispatchQueue(label: "com.unplugged.local-network-permission")
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var observers: [NSObjectProtocol] = []
    private var didFinish = false
    private var didResignActive = false
    private var didObserveDeniedState = false
    private var promptDismissalCheckCount = 0
    private let serviceName = "unplugged-permission-\(UUID().uuidString)"
    private let bonjourType = "_\(ProximityConstants.serviceType)._tcp"

    private enum Timing {
        static let noPromptDeniedDelay: DispatchTimeInterval = .seconds(3)
        static let promptDismissalPollDelay: DispatchTimeInterval = .milliseconds(200)
        static let promptDismissalMaxPolls = 20
        static let backstopDelay: DispatchTimeInterval = .seconds(30)
    }

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func start() {
        log("Proximity permission check started")
        let browserParameters = NWParameters.tcp
        browserParameters.includePeerToPeer = true
        let listenerParameters = NWParameters.tcp
        listenerParameters.includePeerToPeer = true

        do {
            let listener = try NWListener(using: listenerParameters)
            listener.service = NWListener.Service(name: serviceName, type: bonjourType)
            listener.newConnectionHandler = { connection in
                connection.cancel()
            }
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    self.log("Proximity permission probe published")
                case .failed(let error):
                    self.log("Proximity permission probe failed: \(String(describing: error))")
                    if error.isLocalNetworkDenied {
                        self.observeDeniedState("Proximity permission probe denied by policy")
                    } else {
                        self.finish(true)
                    }
                case .waiting(let error):
                    if error.isLocalNetworkDenied {
                        self.observeDeniedState("Proximity permission probe waiting with local-network denial")
                    }
                case .cancelled:
                    break
                default:
                    break
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            AppLogger.touchTips.error("Local Network permission probe could not start NWListener", error: error)
            finish(true)
            return
        }

        let browser = NWBrowser(
            for: .bonjour(type: bonjourType, domain: nil),
            using: browserParameters
        )
        self.browser = browser

#if canImport(UIKit)
        let resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            self.queue.async { self.didResignActive = true }
        }
        let becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            self.queue.async {
                // Only treat didBecomeActive as a dialog-dismissal signal
                // if we previously saw willResignActive. Otherwise this is
                // the launch-time activation and we ignore it.
                guard self.didResignActive else { return }
                self.log("Proximity permission prompt dismissed, waiting for probe")
                self.scheduleDismissalResolution()
            }
        }
        observers = [resignObserver, becomeActiveObserver]
#endif

        // Hard backstop: if nothing resolves within 30 s (e.g. no dialog was
        // ever shown AND the browser stays in .waiting), call it denied so
        // onboarding doesn't hang forever.
        queue.asyncAfter(deadline: .now() + Timing.backstopDelay) { [self] in
            guard !self.didFinish else { return }
            guard !self.didResignActive else {
                self.log("Proximity permission backstop deferred while prompt is active")
                return
            }
            self.log("Proximity permission check hit 30s backstop")
            self.finish(false)
        }

        browser.browseResultsChangedHandler = { [self] results, _ in
            if results.contains(where: { $0.endpoint.matchesBonjourService(named: self.serviceName, type: self.bonjourType) }) {
                self.log("Proximity permission browser found probe")
                self.finish(true)
            }
        }

        browser.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                self.log("Proximity browser ready, waiting for permission probe")
            case .failed(let error):
                // .failed is terminal. Non-EPERM failures still prove the
                // browser had permission to try — treat them as allowed so
                // we don't flag the user for a transient Bonjour hiccup.
                self.log("Proximity browser failed: \(String(describing: error))")
                if error.isLocalNetworkDenied {
                    self.observeDeniedState("Proximity browser failed with local-network denial")
                } else {
                    self.finish(true)
                }
            case .waiting(let error):
                // `.waiting(EPERM)` without an app lifecycle change means the
                // system skipped the dialog (previously denied). Wait briefly
                // to let willResignActive land if the dialog is actually
                // about to appear, then treat it as denied.
                if error.isLocalNetworkDenied {
                    self.observeDeniedState("Proximity browser waiting with local-network denial")
                }
            case .cancelled:
                break
            default:
                break
            }
        }

        browser.start(queue: queue)
    }

    private func finish(_ allowed: Bool) {
        // Serialize on our queue so the multiple completion paths
        // (stateUpdateHandler, lifecycle observers, backstop timer) can't
        // race to resume the continuation twice.
        queue.async { [self] in
            guard !self.didFinish else { return }
            self.didFinish = true
            self.log("Proximity permission check finished: \(allowed ? "allowed" : "denied")")
            self.browser?.cancel()
            self.browser = nil
            self.listener?.cancel()
            self.listener = nil
            for observer in self.observers {
                NotificationCenter.default.removeObserver(observer)
            }
            self.observers.removeAll()
            self.continuation.resume(returning: allowed)
        }
    }

    private func observeDeniedState(_ message: String) {
        guard !didFinish else { return }
        didObserveDeniedState = true
        log(message)

        guard !didResignActive else { return }
        queue.asyncAfter(deadline: .now() + Timing.noPromptDeniedDelay) { [weak self] in
            guard let self,
                  !self.didFinish,
                  self.didObserveDeniedState,
                  !self.didResignActive else { return }
            self.log("Proximity permission denied without prompt dismissal")
            self.finish(false)
        }
    }

    private func scheduleDismissalResolution() {
        promptDismissalCheckCount = 0
        log("Proximity permission dismissal polling started")
        pollForProbeAfterPrompt()
    }

    private func pollForProbeAfterPrompt() {
        guard !didFinish else { return }
        guard didResignActive else { return }

        // After the prompt is dismissed, give Bonjour a short window to find
        // our probe. The result handler finishes with approval if it appears.
        promptDismissalCheckCount += 1
        log("Proximity permission polling attempt \(promptDismissalCheckCount)")
        if promptDismissalCheckCount >= Timing.promptDismissalMaxPolls {
            finish(false)
            return
        }

        queue.asyncAfter(deadline: .now() + Timing.promptDismissalPollDelay) { [weak self] in
            self?.pollForProbeAfterPrompt()
        }
    }

    /// Routes through AppLogger.touchTips so the kill switch silences the
    /// chatty proximity pairing trace. Level is `.info` — individual failure
    /// sites use `.warning` / `.error` directly where they matter.
    private func log(_ message: String) {
        AppLogger.touchTips.info(message)
    }
}

private extension NWError {
    var isLocalNetworkDenied: Bool {
        switch self {
        case .posix(let code):
            return code == .EPERM
        case .dns(let code):
            // kDNSServiceErr_PolicyDenied. Use the numeric value to avoid
            // depending on dns_sd.h availability in this target.
            return Int(code) == -65_570
        default:
            return false
        }
    }
}

private extension NWEndpoint {
    func matchesBonjourService(named name: String, type: String) -> Bool {
        guard case let .service(endpointName, endpointType, _, _) = self else { return false }
        return endpointName == name && endpointType == type
    }
}

// MARK: - Delegate bridge
//
// MultipeerConnectivity and NearbyInteraction delegates are @objc and called from
// arbitrary queues, so they can't live on the actor. This bridge captures events and
// forwards them into the actor via closures the actor sets in `wireBridge()`.

private final class ProximityBridge:
    NSObject,
    MCSessionDelegate,
    MCNearbyServiceAdvertiserDelegate,
    MCNearbyServiceBrowserDelegate,
    NISessionDelegate,
    @unchecked Sendable
{
    var onFoundPeer: ((MCPeerID, [String: String]?) -> Void)?
    var onInvitation: ((MCPeerID, @escaping (Bool, MCSession?) -> Void) -> Void)?
    var onSessionState: ((MCPeerID, MCSessionState) -> Void)?
    var onDataReceived: ((MCPeerID, Data) -> Void)?
    var onNIUpdate: (([NINearbyObject]) -> Void)?
    var onNIRemoved: (([NINearbyObject]) -> Void)?
    var onNIInvalidated: ((Error) -> Void)?
    var onLostPeer: ((MCPeerID) -> Void)?
    var onBrowserFailure: ((Error) -> Void)?
    var onAdvertiserFailure: ((Error) -> Void)?
    var onNISuspended: (() -> Void)?
    var onNISuspensionEnded: (() -> Void)?

    // MCNearbyServiceBrowserDelegate
    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        onFoundPeer?(peerID, info)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        onLostPeer?(peerID)
    }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        onBrowserFailure?(error)
    }

    // MCNearbyServiceAdvertiserDelegate
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        onInvitation?(peerID, invitationHandler)
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        onAdvertiserFailure?(error)
    }

    // MCSessionDelegate
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        onSessionState?(peerID, state)
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        onDataReceived?(peerID, data)
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // NISessionDelegate
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        onNIUpdate?(nearbyObjects)
    }
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        onNIRemoved?(nearbyObjects)
    }
    func sessionWasSuspended(_ session: NISession) {
        onNISuspended?()
    }
    func sessionSuspensionEnded(_ session: NISession) {
        onNISuspensionEnded?()
    }
    func session(_ session: NISession, didInvalidateWith error: Error) {
        onNIInvalidated?(error)
    }
}

private extension MCSessionState {
    var logDescription: String {
        switch self {
        case .notConnected:
            return "notConnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        @unknown default:
            return "unknown(\(rawValue))"
        }
    }
}
