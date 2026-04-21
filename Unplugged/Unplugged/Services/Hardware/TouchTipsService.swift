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
//    5. When distance <= ProximityConstants.touchThresholdMeters (≈15 cm), the
//       joiner yields the room UUID on its AsyncStream and auto-joins — no buttons.
//
//  Fallback
//  ────────
//  If NearbyInteraction is unavailable (pre-U1 device, denied permission, older iOS),
//  we yield the room UUID as soon as MC negotiates a secure session. MC is radio-
//  proximity bounded (BT LE / P2P Wi-Fi, <10 m), so this is a looser but still-local
//  gate. The explicit "bring phones together" hint in the UI copy still applies.
//

import Foundation
import MultipeerConnectivity
import NearbyInteraction
import UnpluggedShared

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

    func stop() {
        stopInternal(keepContinuation: false)
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
    }

    private var role: Role = .none
    private var continuation: AsyncStream<UUID>.Continuation?

    private let bridge: ProximityBridge
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var mcSession: MCSession?
    private var localPeerID: MCPeerID?

    /// roomID pulled from discoveryInfo on the joiner side, keyed by the peer we invited.
    /// Used as a fallback if the handshake message arrives before we've parsed the payload,
    /// or if the host never sends a roomID for some reason.
    private var discoveredRoomID: [MCPeerID: UUID] = [:]

    private var niSession: NISession?
    private var peerDiscoveryToken: NIDiscoveryToken?
    private var didYield = false

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
        }
        bridge.onNIInvalidated = { [weak self] _ in
            Task { await self?.resetNI() }
        }
    }

    // MARK: - MC event handlers

    private func handleFoundPeer(peer: MCPeerID, info: [String: String]?) {
        guard case .joiner = role,
              let session = mcSession,
              let browser = browser else { return }
        if let uuidString = info?["roomID"], let roomID = UUID(uuidString: uuidString) {
            discoveredRoomID[peer] = roomID
        }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 15)
    }

    private func handleInvitation(peer: MCPeerID, handler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept any inbound invite on our namespaced service — the service type
        // itself is the coarse gate; UWB is the fine gate.
        handler(true, mcSession)
    }

    private func handleSessionState(peer: MCPeerID, state: MCSessionState) {
        guard state == .connected else { return }
        sendHandshake(to: peer)
        // Fallback: if NI never fires (device lacks U1 or permission denied), the
        // connection itself is our proximity proof. We give NI a short window to
        // claim the pairing first.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self?.yieldIfStillWaiting(reason: "MC-only fallback")
        }
    }

    private func sendHandshake(to peer: MCPeerID) {
        guard let session = mcSession else { return }

        // Start our own NISession and get its discovery token to send.
        let ni: NISession?
        if NISession.deviceCapabilities.supportsPreciseDistanceMeasurement {
            ni = NISession()
            ni?.delegate = bridge
            niSession = ni
        } else {
            ni = nil
        }

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
        if case .joiner = role,
           let uuidString = payload["roomID"],
           let roomID = UUID(uuidString: uuidString) {
            discoveredRoomID[peer] = roomID
        }

        // Extract NI discovery token and start the NI session against it.
        guard let tokenB64 = payload["niToken"],
              let tokenData = Data(base64Encoded: tokenB64),
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: tokenData) else {
            return
        }
        peerDiscoveryToken = token
        startNIRanging(with: token)
    }

    private func startNIRanging(with token: NIDiscoveryToken) {
        if niSession == nil, NISession.deviceCapabilities.supportsPreciseDistanceMeasurement {
            let ni = NISession()
            ni.delegate = bridge
            niSession = ni
        }
        guard let ni = niSession else { return }
        let config = NINearbyPeerConfiguration(peerToken: token)
        ni.run(config)
    }

    // MARK: - NI event handler

    private func handleNIUpdate(objects: [NINearbyObject]) {
        guard !didYield else { return }
        let token = peerDiscoveryToken
        let match = objects.first { $0.discoveryToken == token }
        guard let distance = match?.distance,
              distance <= Float(ProximityConstants.touchThresholdMeters) else { return }
        yieldIfStillWaiting(reason: "UWB <\(ProximityConstants.touchThresholdMeters)m")
    }

    private func resetNI() {
        niSession = nil
        peerDiscoveryToken = nil
    }

    // MARK: - Yielding

    private func yieldIfStillWaiting(reason: String) {
        guard !didYield, case .joiner = role, let continuation else { return }
        // Pick any room we've learned about. In practice there's only one peer at a time.
        guard let roomID = discoveredRoomID.values.first else { return }
        didYield = true
        continuation.yield(roomID)
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

        niSession?.invalidate()
        niSession = nil
        peerDiscoveryToken = nil

        localPeerID = nil
        discoveredRoomID.removeAll()
        role = .none

        if !keepContinuation {
            continuation?.finish()
            continuation = nil
            didYield = false
        }
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
