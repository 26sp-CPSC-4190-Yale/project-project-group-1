import Foundation
import MultipeerConnectivity
import NearbyInteraction
import UnpluggedShared

final class TouchTipsService: NSObject, ProximityProviding, @unchecked Sendable {

    nonisolated(unsafe) var onDistanceUpdate: (@Sendable (Double?) -> Void)?
    nonisolated(unsafe) var onRoomReceived: (@Sendable (UUID) -> Void)?

    nonisolated(unsafe) private var peerID: MCPeerID?
    nonisolated(unsafe) private var advertiser: MCNearbyServiceAdvertiser?
    nonisolated(unsafe) private var browser: MCNearbyServiceBrowser?
    nonisolated(unsafe) private var mcSession: MCSession?
    nonisolated(unsafe) private var niSession: NISession?
    nonisolated(unsafe) private var niTokenData: Data?
    nonisolated(unsafe) private var roomID: UUID?
    nonisolated(unsafe) private var hasSentRoomID = false
    nonisolated(unsafe) private var peerNIToken: NIDiscoveryToken?

    private nonisolated var supportsNI: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    private enum MessageTag: UInt8 {
        case niToken = 0x01
        case roomID = 0x02
    }

    func startAdvertising(roomID: UUID, userID: UUID) {
        stopSession()
        self.roomID = roomID
        self.hasSentRoomID = false

        prepareNISession()

        let peer = MCPeerID(displayName: userID.uuidString)
        self.peerID = peer

        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.mcSession = session

        let adv = MCNearbyServiceAdvertiser(
            peer: peer,
            discoveryInfo: ["role": "host"],
            serviceType: ProximityConstants.serviceType
        )
        adv.delegate = self
        self.advertiser = adv
        adv.startAdvertisingPeer()
    }

    func startBrowsing(userID: UUID) {
        stopSession()
        self.roomID = nil
        self.hasSentRoomID = false

        prepareNISession()

        let peer = MCPeerID(displayName: userID.uuidString)
        self.peerID = peer

        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.mcSession = session

        let brw = MCNearbyServiceBrowser(peer: peer, serviceType: ProximityConstants.serviceType)
        brw.delegate = self
        self.browser = brw
        brw.startBrowsingForPeers()
    }

    func stop() {
        stopSession()
        onDistanceUpdate = nil
        onRoomReceived = nil
    }

    private func stopSession() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        mcSession?.disconnect()
        mcSession = nil
        niSession?.invalidate()
        niSession = nil
        niTokenData = nil
        peerNIToken = nil
        roomID = nil
        hasSentRoomID = false
    }

    private func prepareNISession() {
        guard supportsNI else { return }
        let ni = NISession()
        ni.delegate = self
        self.niSession = ni

        guard let token = ni.discoveryToken,
              let data = try? NSKeyedArchiver.archivedData(
                  withRootObject: token,
                  requiringSecureCoding: true
              ) else { return }
        self.niTokenData = data
    }

    private func sendStoredNIToken(to peer: MCPeerID) {
        guard let tokenData = niTokenData else { return }
        var message = Data([MessageTag.niToken.rawValue])
        message.append(tokenData)
        try? mcSession?.send(message, toPeers: [peer], with: .reliable)
    }

    private func runNISession(with peerToken: NIDiscoveryToken) {
        self.peerNIToken = peerToken
        guard let ni = niSession else { return }
        let config = NINearbyPeerConfiguration(peerToken: peerToken)
        ni.run(config)
    }

    private func sendRoomID(to peer: MCPeerID) {
        guard let roomID = roomID, !hasSentRoomID else { return }
        hasSentRoomID = true

        var message = Data([MessageTag.roomID.rawValue])
        withUnsafeBytes(of: roomID.uuid) { message.append(contentsOf: $0) }

        try? mcSession?.send(message, toPeers: [peer], with: .reliable)
    }
}

extension TouchTipsService: @preconcurrency MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, mcSession)
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
}

extension TouchTipsService: @preconcurrency MCNearbyServiceBrowserDelegate {

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard info?["role"] == "host", let session = mcSession else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
}

extension TouchTipsService: @preconcurrency MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard state == .connected else { return }

        if supportsNI {
            sendStoredNIToken(to: peerID)
        } else if roomID != nil {
            sendRoomID(to: peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let tag = data.first, let messageTag = MessageTag(rawValue: tag) else { return }
        let payload = data.dropFirst()

        switch messageTag {
        case .niToken:
            guard let token = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NIDiscoveryToken.self,
                from: Data(payload)
            ) else { return }
            runNISession(with: token)

        case .roomID:
            guard payload.count == 16 else { return }
            let uuid = payload.withUnsafeBytes { buffer -> UUID in
                var uuidBytes: uuid_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
                withUnsafeMutableBytes(of: &uuidBytes) { dest in
                    dest.copyBytes(from: buffer)
                }
                return UUID(uuid: uuidBytes)
            }
            onRoomReceived?(uuid)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension TouchTipsService: @preconcurrency NISessionDelegate {

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let nearest = nearbyObjects.first, let distance = nearest.distance else {
            onDistanceUpdate?(nil)
            return
        }

        onDistanceUpdate?(Double(distance))

        if Double(distance) <= ProximityConstants.touchThresholdMeters,
           let peer = mcSession?.connectedPeers.first {
            if roomID != nil {
                sendRoomID(to: peer)
            }
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        onDistanceUpdate?(nil)
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {}

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        guard let token = peerNIToken else { return }
        let config = NINearbyPeerConfiguration(peerToken: token)
        session.run(config)
    }
}
