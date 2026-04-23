// GroupActivities is FaceTime-relayed, not on-device proximity. iOS 17+ intercepts tips-together as NameDrop, which third-party apps can't override
// UWB is the ONLY auto-pair gate. MC alone is ~10m range. Do NOT reintroduce an "if MC connects, assume proximity" shortcut, users will pair from across the room

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
        publishLockedSignalLoss(reason: "monitor_started")
        return stream
    }

    func supportsLockedProximityMonitoring() -> Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    func stop() {
        stopInternal(keepContinuation: false)
    }

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

    private var discoveredRoomID: [MCPeerID: UUID] = [:]
    private var pendingPeerInvitations: Set<String> = []

    private var niSessions: [MCPeerID: NISession] = [:]
    private var peerDiscoveryTokens: [MCPeerID: NIDiscoveryToken] = [:]
    private var didYield = false

    // require N consecutive sub-threshold samples, a single sub-10cm spike from a hand wave is not proof the phones are together
    private var consecutiveCloseCount: Int = 0

    private var lastLockedProximityEmitAt: Date?
    private static let lockedProximityMinInterval: TimeInterval = 0.3

    // MARK: - Wire delegate callbacks

    private func wireBridge() {
        bridge.onFoundPeer = { [weak self] browser, peer, info in
            Task { await self?.handleFoundPeer(browser: browser, peer: peer, info: info) }
        }
        bridge.onInvitation = { [weak self] advertiser, peer, invitationHandler in
            Task { await self?.handleInvitation(advertiser: advertiser, peer: peer, handler: invitationHandler) }
        }
        bridge.onSessionState = { [weak self] session, peer, state in
            Task { await self?.handleSessionState(session: session, peer: peer, state: state) }
        }
        bridge.onDataReceived = { [weak self] session, peer, data in
            Task { await self?.handleDataReceived(session: session, peer: peer, data: data) }
        }
        bridge.onNIUpdate = { [weak self] session, objects in
            Task { await self?.handleNIUpdate(session: session, objects: objects) }
        }
        bridge.onNIRemoved = { [weak self] session, _ in
            // do not tear down MC, the peer can approach again without re-pairing
            Task { await self?.handleNIRemoved(session: session) }
        }
        bridge.onNIInvalidated = { [weak self] session, error in
            Task { await self?.resetNI(session: session, reason: String(describing: error)) }
        }
        bridge.onLostPeer = { [weak self] browser, peer in
            Task { await self?.handleLostPeer(browser: browser, peer: peer) }
        }
        bridge.onBrowserFailure = { [weak self] browser, error in
            Task { await self?.handleBrowserFailure(browser: browser, error) }
        }
        bridge.onAdvertiserFailure = { [weak self] advertiser, error in
            Task { await self?.handleAdvertiserFailure(advertiser: advertiser, error) }
        }
        bridge.onNISuspended = { [weak self] session in
            Task { await self?.handleNISuspended(session: session) }
        }
        bridge.onNISuspensionEnded = { [weak self] session in
            Task { await self?.handleNISuspensionEnded(session: session) }
        }
    }

    // MARK: - MC event handlers

    private func handleFoundPeer(browser: MCNearbyServiceBrowser, peer: MCPeerID, info: [String: String]?) {
        guard let session = mcSession,
              let activeBrowser = self.browser,
              browser === activeBrowser else {
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

        if pendingPeerInvitations.contains(peer.displayName) {
            log("ignoring duplicate invite attempt for \(peer.displayName)")
            return
        }
        if session.connectedPeers.contains(where: { $0.displayName == peer.displayName }) {
            log("ignoring already-connected peer \(peer.displayName)")
            return
        }

        pendingPeerInvitations.insert(peer.displayName)
        log("inviting peer \(peer.displayName) for role \(roleLogDescription)")
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 15)
    }

    private func handleInvitation(advertiser: MCNearbyServiceAdvertiser, peer: MCPeerID, handler: @escaping (Bool, MCSession?) -> Void) {
        guard advertiser === self.advertiser else {
            handler(false, nil)
            return
        }
        // auto-accept, service type is the coarse gate and UWB is the fine gate
        log("received invitation from \(peer.displayName), accepting: \(mcSession != nil ? "YES" : "NO_SESSION")")
        handler(true, mcSession)
    }

    private func handleSessionState(session: MCSession, peer: MCPeerID, state: MCSessionState) {
        guard session === mcSession else { return }
        log("MC session state for \(peer.displayName): \(state.logDescription) role: \(roleLogDescription)")
        if state == .connected {
            pendingPeerInvitations.remove(peer.displayName)
            sendHandshake(to: peer)
        } else {
            if state == .notConnected {
                pendingPeerInvitations.remove(peer.displayName)
            }
            niSessions[peer]?.invalidate()
            niSessions[peer] = nil
            peerDiscoveryTokens[peer] = nil
            if case .lockedGuest = role {
                publishLockedSignalLoss(reason: "mc_\(state.logDescription)")
            }
        }
        // do NOT yield on MC connect, MC is ~10m radio proximity, UWB in handleNIUpdate is the actual touch gate
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
                publishLockedSignalLoss(reason: "handshake_send_failed")
            }
        }
    }

    private func handleDataReceived(session: MCSession, peer: MCPeerID, data: Data) {
        guard session === mcSession else { return }
        let payload: [String: String]
        do {
            payload = try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            AppLogger.touchTips.error("inbound data decode failed", error: error, context: ["peer": peer.displayName, "bytes": data.count])
            return
        }
        log("data received from \(peer.displayName): roomID=\(payload["roomID"] != nil ? "YES" : "NO"), niToken=\(payload["niToken"] != nil ? "YES" : "NO")")

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

        guard let tokenB64 = payload["niToken"],
              let tokenData = Data(base64Encoded: tokenB64),
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: tokenData) else {
            log("NI token missing/invalid from \(peer.displayName)")
            if case .lockedGuest = role {
                publishLockedSignalLoss(reason: "ni_token_missing")
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
                publishLockedSignalLoss(reason: "uwb_unsupported")
            }
            return
        }
        let config = NINearbyPeerConfiguration(peerToken: token)
        ni.run(config)
        log("NI ranging started for \(peer.displayName)")
    }

    // MARK: - NI event handler

    private func handleNIUpdate(session: NISession, objects: [NINearbyObject]) {
        guard hasActiveNISession(session) else { return }
        let match = objects.compactMap { object -> Float? in
            guard let distance = object.distance else { return nil }
            return peerDiscoveryTokens.values.contains { $0 == object.discoveryToken } ? distance : nil
        }.first

        guard let distance = match else {
            consecutiveCloseCount = 0
            if case .lockedGuest = role {
                publishLockedSignalLoss(reason: "ni_update_without_distance")
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
            consecutiveCloseCount = 0
        }
    }

    private func handleNIRemoved(session: NISession) {
        guard hasActiveNISession(session) else { return }
        consecutiveCloseCount = 0
        if case .lockedGuest = role {
            log("NI peer removed while locked monitor active")
            publishLockedSignalLoss(reason: "ni_peer_removed")
        }
    }

    private func resetNI(session: NISession, reason: String) {
        guard hasActiveNISession(session) else { return }
        log("NI reset for role \(roleLogDescription), reason: \(reason)")
        for session in niSessions.values {
            session.invalidate()
        }
        niSessions.removeAll()
        peerDiscoveryTokens.removeAll()
        consecutiveCloseCount = 0
        if case .lockedGuest = role {
            publishLockedSignalLoss(reason: "ni_invalidated")
        }
    }

    private func handleLostPeer(browser: MCNearbyServiceBrowser, peer: MCPeerID) {
        guard browser === self.browser else { return }
        log("lost peer \(peer.displayName) for role \(roleLogDescription)")
        pendingPeerInvitations.remove(peer.displayName)
        niSessions[peer]?.invalidate()
        niSessions[peer] = nil
        peerDiscoveryTokens[peer] = nil
        if case .lockedGuest = role {
            publishLockedSignalLoss(reason: "mc_lost_peer")
        }
    }

    private func handleBrowserFailure(browser: MCNearbyServiceBrowser, _ error: Error) {
        guard browser === self.browser else { return }
        AppLogger.touchTips.error("MC browser failed", error: error, context: ["role": roleLogDescription])
        if case .lockedGuest = role {
            publishLockedSignalLoss(reason: "browser_failed")
        }
    }

    private func handleAdvertiserFailure(advertiser: MCNearbyServiceAdvertiser, _ error: Error) {
        guard advertiser === self.advertiser else { return }
        AppLogger.touchTips.error("MC advertiser failed", error: error, context: ["role": roleLogDescription])
    }

    private func handleNISuspended(session: NISession) {
        guard hasActiveNISession(session) else { return }
        log("NI suspended for role \(roleLogDescription)")
        if case .lockedGuest = role {
            publishLockedSignalLoss(reason: "ni_suspended")
        }
    }

    private func handleNISuspensionEnded(session: NISession) {
        guard hasActiveNISession(session) else { return }
        log("NI suspension ended for role \(roleLogDescription)")
    }

    // MARK: - Yielding

    private func yieldIfStillWaiting(reason: String) {
        guard !didYield, case .joiner = role, let continuation else { return }
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
        let now = Date()
        // throttle non-nil readings only, nil carries state transitions that must always propagate
        if distanceMeters != nil,
           let last = lastLockedProximityEmitAt,
           now.timeIntervalSince(last) < Self.lockedProximityMinInterval {
            return
        }
        if distanceMeters == nil {
            log("locked monitor emitted no-distance reading, reason: \(reason ?? "unknown")")
        }
        lastLockedProximityEmitAt = now
        lockedProximityContinuation?.yield(
            LockedProximityReading(distanceMeters: distanceMeters, observedAt: now, reason: reason)
        )
    }

    private func hasActiveNISession(_ session: NISession) -> Bool {
        niSessions.values.contains { $0 === session }
    }

    private func publishLockedSignalLoss(reason: String) {
        guard case .lockedGuest = role else { return }
        guard Self.shouldEmitLockedNoDistance(for: reason) else {
            log("locked monitor observed transient signal gap, preserving last distance, reason: \(reason)")
            return
        }
        emitLockedProximity(distanceMeters: nil, reason: reason)
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
        pendingPeerInvitations.removeAll()

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

extension TouchTipsService {
    nonisolated static func shouldEmitLockedNoDistance(for reason: String) -> Bool {
        switch reason {
        case "monitor_started", "mc_connecting", "ni_update_without_distance":
            return false
        default:
            return true
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

// NWBrowser.State.ready can arrive before the Local Network alert is answered, the Bonjour probe is what actually proves approval
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
                // only treat didBecomeActive as dismissal if we saw willResignActive first, launch activation is not dismissal
                guard self.didResignActive else { return }
                self.log("Proximity permission prompt dismissed, waiting for probe")
                self.scheduleDismissalResolution()
            }
        }
        observers = [resignObserver, becomeActiveObserver]
#endif

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
                // non-EPERM failures prove the browser had permission, treat as allowed
                self.log("Proximity browser failed: \(String(describing: error))")
                if error.isLocalNetworkDenied {
                    self.observeDeniedState("Proximity browser failed with local-network denial")
                } else {
                    self.finish(true)
                }
            case .waiting(let error):
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
        // serialize on our queue, multiple completion paths must not race to resume the continuation twice
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
            // kDNSServiceErr_PolicyDenied, numeric to avoid the dns_sd.h dependency
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

// MC/NI delegates are @objc and called from arbitrary queues so they cannot live on the actor, bridge forwards events in
private final class ProximityBridge:
    NSObject,
    MCSessionDelegate,
    MCNearbyServiceAdvertiserDelegate,
    MCNearbyServiceBrowserDelegate,
    NISessionDelegate,
    @unchecked Sendable
{
    // framework delegates arrive off the main actor, closures must be callable from nonisolated context
    nonisolated(unsafe) var onFoundPeer: ((MCNearbyServiceBrowser, MCPeerID, [String: String]?) -> Void)?
    nonisolated(unsafe) var onInvitation: ((MCNearbyServiceAdvertiser, MCPeerID, @escaping (Bool, MCSession?) -> Void) -> Void)?
    nonisolated(unsafe) var onSessionState: ((MCSession, MCPeerID, MCSessionState) -> Void)?
    nonisolated(unsafe) var onDataReceived: ((MCSession, MCPeerID, Data) -> Void)?
    nonisolated(unsafe) var onNIUpdate: ((NISession, [NINearbyObject]) -> Void)?
    nonisolated(unsafe) var onNIRemoved: ((NISession, [NINearbyObject]) -> Void)?
    nonisolated(unsafe) var onNIInvalidated: ((NISession, Error) -> Void)?
    nonisolated(unsafe) var onLostPeer: ((MCNearbyServiceBrowser, MCPeerID) -> Void)?
    nonisolated(unsafe) var onBrowserFailure: ((MCNearbyServiceBrowser, Error) -> Void)?
    nonisolated(unsafe) var onAdvertiserFailure: ((MCNearbyServiceAdvertiser, Error) -> Void)?
    nonisolated(unsafe) var onNISuspended: ((NISession) -> Void)?
    nonisolated(unsafe) var onNISuspensionEnded: ((NISession) -> Void)?

    // MCNearbyServiceBrowserDelegate
    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        onFoundPeer?(browser, peerID, info)
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        onLostPeer?(browser, peerID)
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        onBrowserFailure?(browser, error)
    }

    // MCNearbyServiceAdvertiserDelegate
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        onInvitation?(advertiser, peerID, invitationHandler)
    }
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        onAdvertiserFailure?(advertiser, error)
    }

    // MCSessionDelegate
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        onSessionState?(session, peerID, state)
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        onDataReceived?(session, peerID, data)
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // NISessionDelegate
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        onNIUpdate?(session, nearbyObjects)
    }
    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        onNIRemoved?(session, nearbyObjects)
    }
    nonisolated func sessionWasSuspended(_ session: NISession) {
        onNISuspended?(session)
    }
    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        onNISuspensionEnded?(session)
    }
    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        onNIInvalidated?(session, error)
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
