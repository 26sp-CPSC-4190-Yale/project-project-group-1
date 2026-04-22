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

        let stream = AsyncStream<LockedProximityReading> { cont in
            self.lockedProximityContinuation = cont
        }

        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            emitLockedProximity(distanceMeters: nil)
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

        emitLockedProximity(distanceMeters: nil)
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
        self.bridge = ProximityBridge()
        Task { await self.wireBridge() }
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

    // MARK: - Wire delegate callbacks

    private func wireBridge() {
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
        bridge.onNIInvalidated = { [weak self] _ in
            Task { await self?.resetNI() }
        }
    }

    // MARK: - MC event handlers

    private func handleFoundPeer(peer: MCPeerID, info: [String: String]?) {
        guard let session = mcSession,
              let browser = browser else { return }

        if let uuidString = info?["roomID"], let roomID = UUID(uuidString: uuidString) {
            discoveredRoomID[peer] = roomID
        }

        switch role {
        case .joiner:
            break
        case .lockedGuest(let roomID):
            guard discoveredRoomID[peer] == roomID else { return }
        case .none, .host:
            return
        }

        browser.invitePeer(peer, to: session, withContext: nil, timeout: 15)
    }

    private func handleInvitation(peer: MCPeerID, handler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept any inbound invite on our namespaced service — the service type
        // itself is the coarse gate; UWB is the fine gate.
        handler(true, mcSession)
    }

    private func handleSessionState(peer: MCPeerID, state: MCSessionState) {
        if state == .connected {
            sendHandshake(to: peer)
        } else {
            niSessions[peer]?.invalidate()
            niSessions[peer] = nil
            peerDiscoveryTokens[peer] = nil
            if case .lockedGuest = role {
                emitLockedProximity(distanceMeters: nil)
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

        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? session.send(data, toPeers: [peer], with: .reliable)
    }

    private func handleDataReceived(peer: MCPeerID, data: Data) {
        guard let payload = try? JSONDecoder().decode([String: String].self, from: data) else { return }

        // Capture host's roomID if we didn't already have it from discoveryInfo.
        if (isJoiner || isLockedGuest),
           let uuidString = payload["roomID"],
           let roomID = UUID(uuidString: uuidString) {
            discoveredRoomID[peer] = roomID
        }

        if case .lockedGuest(let expectedRoomID) = role,
           let roomID = discoveredRoomID[peer],
           roomID != expectedRoomID {
            return
        }

        // Extract NI discovery token and start the NI session against it.
        guard let tokenB64 = payload["niToken"],
              let tokenData = Data(base64Encoded: tokenB64),
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: tokenData) else {
            return
        }
        peerDiscoveryTokens[peer] = token
        startNIRanging(with: token, peer: peer)
    }

    private func startNIRanging(with token: NIDiscoveryToken, peer: MCPeerID) {
        guard let ni = makeNISession(for: peer) else { return }
        let config = NINearbyPeerConfiguration(peerToken: token)
        ni.run(config)
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
            emitLockedProximity(distanceMeters: nil)
        }
    }

    private func resetNI() {
        for session in niSessions.values {
            session.invalidate()
        }
        niSessions.removeAll()
        peerDiscoveryTokens.removeAll()
        consecutiveCloseCount = 0
        if case .lockedGuest = role {
            emitLockedProximity(distanceMeters: nil)
        }
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
        return ni
    }

    private func emitLockedProximity(distanceMeters: Double?) {
        lockedProximityContinuation?.yield(
            LockedProximityReading(distanceMeters: distanceMeters, observedAt: Date())
        )
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
/// Why not a simple timer? `NWBrowser` fires `.waiting(.posix(.EPERM))`
/// *immediately* on start, before the system alert even renders. The previous
/// implementation scheduled `finish(false)` 5 seconds after that event — which
/// fired while the user was still reading the dialog, so onboarding advanced
/// to the Screen Time step with the Local Network alert still on screen.
///
/// Instead, we piggy-back on UIApplication lifecycle: iOS permission alerts
/// cause `willResignActive` as they appear and `didBecomeActive` as the user
/// taps Allow or Deny. When we see the dismissal edge we check the browser
/// state — `.ready` means allowed, anything else means denied. A long hard
/// backstop (30 s) covers the rare case where neither event fires (e.g.
/// permission was already denied in a previous run so no dialog is shown).
private final class LocalNetworkPermissionResolver: @unchecked Sendable {
    private let continuation: CheckedContinuation<Bool, Never>
    private let queue = DispatchQueue(label: "com.unplugged.local-network-permission")
    private var browser: NWBrowser?
    private var observers: [NSObjectProtocol] = []
    private var didFinish = false
    private var didResignActive = false
    private var didReachReady = false
    private var promptDismissalCheckCount = 0

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func start() {
        log("Proximity permission check started")
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let bonjourType = "_\(ProximityConstants.serviceType)._tcp"
        let browser = NWBrowser(
            for: .bonjour(type: bonjourType, domain: nil),
            using: parameters
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
                self.log("Proximity permission prompt dismissed, waiting for browser state")
                self.scheduleDismissalResolution()
            }
        }
        observers = [resignObserver, becomeActiveObserver]
#endif

        // Hard backstop: if nothing resolves within 30 s (e.g. no dialog was
        // ever shown AND the browser stays in .waiting), call it denied so
        // onboarding doesn't hang forever.
        queue.asyncAfter(deadline: .now() + 30) { [self] in
            self.log("Proximity permission check hit 30s backstop")
            self.finish(self.didReachReady)
        }

        browser.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                self.didReachReady = true
                self.log("Proximity browser reached ready state")
                // If we reached .ready without the app ever resigning active,
                // permission was already granted and no dialog was shown.
                // Resolve immediately.
                if !self.didResignActive {
                    self.finish(true)
                }
            case .failed(let error):
                // .failed is terminal. Non-EPERM failures still prove the
                // browser had permission to try — treat them as allowed so
                // we don't flag the user for a transient Bonjour hiccup.
                self.log("Proximity browser failed: \(String(describing: error))")
                self.finish(!error.isLocalNetworkDenied)
            case .waiting(let error):
                // `.waiting(EPERM)` without an app lifecycle change means the
                // system skipped the dialog (previously denied). Wait briefly
                // to let willResignActive land if the dialog is actually
                // about to appear, then treat it as denied.
                if error.isLocalNetworkDenied {
                    self.log("Proximity browser waiting with EPERM")
                    self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                        guard let self, !self.didResignActive else { return }
                        self.log("Proximity permission denied after EPERM wait")
                        self.finish(false)
                    }
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
        queue.async { [weak self] in
            guard let self, !self.didFinish else { return }
            self.didFinish = true
            self.log("Proximity permission check finished: \(allowed ? "allowed" : "denied")")
            self.browser?.cancel()
            self.browser = nil
            for observer in self.observers {
                NotificationCenter.default.removeObserver(observer)
            }
            self.observers.removeAll()
            self.continuation.resume(returning: allowed)
        }
    }

    private func scheduleDismissalResolution() {
        promptDismissalCheckCount = 0
        log("Proximity permission dismissal polling started")
        pollForReadyAfterPrompt()
    }

    private func pollForReadyAfterPrompt() {
        guard !didFinish else { return }
        guard didResignActive else { return }

        if didReachReady {
            log("Proximity permission check observed ready during polling")
            finish(true)
            return
        }

        // The browser state can lag the app lifecycle edge by a bit longer
        // than the system alert dismissal animation. Poll a few times before
        // we fall back to a denial so we do not misclassify an allowed grant
        // as a rejection and strand onboarding on the warning page.
        promptDismissalCheckCount += 1
        log("Proximity permission polling attempt \(promptDismissalCheckCount)")
        if promptDismissalCheckCount >= 10 {
            finish(false)
            return
        }

        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.pollForReadyAfterPrompt()
        }
    }

    private func log(_ message: String) {
        NSLog("[Unplugged][Proximity] %@", message)
    }
}

private extension NWError {
    var isLocalNetworkDenied: Bool {
        guard case .posix(let code) = self else { return false }
        return code == .EPERM
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

    // MCNearbyServiceBrowserDelegate
    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        onFoundPeer?(peerID, info)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}

    // MCNearbyServiceAdvertiserDelegate
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        onInvitation?(peerID, invitationHandler)
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}

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
    func sessionWasSuspended(_ session: NISession) {}
    func sessionSuspensionEnded(_ session: NISession) {}
    func session(_ session: NISession, didInvalidateWith error: Error) {
        onNIInvalidated?(error)
    }
}
