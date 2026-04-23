//
//  WebSocketClient.swift
//  Unplugged.Services.Networking
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import UnpluggedShared

/// Thin wrapper around `URLSessionWebSocketTask` that emits server-side session events
/// as an `AsyncStream<WSServerMessage>`. The auth token is sent as a Bearer Authorization
/// header on the HTTP upgrade request — query-string auth leaks into access logs and
/// proxy caches, which is why we use the header path.
///
/// On unexpected disconnects the client attempts bounded reconnects with exponential
/// backoff (1s, 2s, 4s, 8s, 16s, 30s) plus jitter, up to `maxReconnectAttempts`.
/// Across reconnects the same `AsyncStream` continuation stays open, so subscribers
/// don't need to re-wire; once all attempts are exhausted the stream finishes.
///
/// Auth-class close codes (1008 policyViolation, 4001, 4003) short-circuit the
/// reconnect loop and fire `unpluggedAuthDidInvalidate` so the app can drop back
/// to the sign-in screen instead of hammering a route that will never accept the
/// current token.
///
/// Inbound messages are wrapped in a `WSServerEnvelope` with a monotonic `seq`. We
/// track the highest seq observed per connection and drop duplicates/out-of-order
/// replays (common on reconnect with server-side catchup).
actor WebSocketClient {
    enum ConnectionState {
        case idle
        case connecting
        case connected
        case disconnected
    }

    private var task: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var continuation: AsyncStream<WSServerMessage>.Continuation?
    private var connectionParams: (sessionID: UUID, token: String)?
    private var reconnectAttempt = 0
    private var shouldReconnect = false
    private(set) var state: ConnectionState = .idle

    /// Monotonic per-connection sequence of the last server envelope we yielded.
    /// Messages with `seq <= lastYieldedSeq` are treated as duplicates and dropped.
    /// Reset on every fresh `connect()` since the server numbers per-connection
    /// (or per-room — either way, an explicit reconnect re-establishes the baseline).
    private var lastYieldedSeq: UInt64 = 0

    /// Counts heartbeat pings without a matching pong. Each ping is considered
    /// outstanding until its completion handler fires; if two ping intervals pass
    /// without one landing, we treat the socket as half-open and force-reconnect.
    private var outstandingHeartbeatPings: Int = 0

    private static let maxReconnectAttempts = 6
    private static let maxBackoffSeconds: UInt64 = 30
    private static let heartbeatIntervalSeconds: UInt64 = 15
    private static let maxOutstandingHeartbeatPings = 2

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Async stream of decoded server messages. A fresh stream is handed out per connect call.
    /// The stream survives transient disconnects — only an explicit `disconnect()` or an
    /// exhausted reconnect budget terminates it.
    func connect(sessionID: UUID, token: String) -> AsyncStream<WSServerMessage> {
        teardownSocket()
        reconnectTask?.cancel()
        reconnectTask = nil
        continuation?.finish()

        let stream = AsyncStream<WSServerMessage> { continuation in
            self.continuation = continuation
        }
        connectionParams = (sessionID, token)
        shouldReconnect = true
        reconnectAttempt = 0
        lastYieldedSeq = 0
        outstandingHeartbeatPings = 0

        openSocket()
        return stream
    }

    func send(_ message: WSClientMessage) async throws {
        guard let task else {
            AppLogger.ws.warning("send called with no live task — dropping message")
            return
        }
        let data: Data
        do {
            data = try encoder.encode(message)
        } catch {
            AppLogger.ws.error("outbound encode failed", error: error)
            throw error
        }
        do {
            try await task.send(.data(data))
        } catch {
            AppLogger.ws.error("task.send failed", error: error)
            throw error
        }
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        teardownSocket()
        continuation?.finish()
        continuation = nil
        connectionParams = nil
        state = .disconnected
    }

    private func openSocket() {
        guard let params = connectionParams else {
            AppLogger.ws.warning("openSocket with no connectionParams — abort")
            return
        }
        state = .connecting
        AppLogger.breadcrumb(.ws, "ws_open_begin", context: ["session": params.sessionID.uuidString, "attempt": reconnectAttempt])

        var components = URLComponents(string: Config.webSocketBaseURL)!
        components.path += "/sessions/\(params.sessionID.uuidString)/ws"

        guard let url = components.url else {
            AppLogger.ws.critical(
                "WebSocket URL construction failed",
                context: ["base": Config.webSocketBaseURL, "session": params.sessionID.uuidString]
            )
            state = .disconnected
            continuation?.finish()
            continuation = nil
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(params.token)", forHTTPHeaderField: "Authorization")

        let task = urlSession.webSocketTask(with: request)
        self.task = task
        outstandingHeartbeatPings = 0
        task.resume()
        state = .connected

        startReceiveLoop()
        startHeartbeat()
    }

    private func teardownSocket() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        outstandingHeartbeatPings = 0
    }

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    guard let message = try await self.receiveOne() else { return }
                    await self.handleIncoming(message)
                } catch {
                    // `self` is still strong from the guard above. If the error
                    // is a close with an auth-class code, short-circuit to
                    // re-auth; otherwise fall through to the standard
                    // disconnect path with backoff reconnect.
                    let closeCode = await self.currentCloseCode()
                    if Self.isAuthCloseCode(closeCode) {
                        AppLogger.ws.warning(
                            "WebSocket closed with auth code — invalidating session",
                            context: ["code": closeCode?.rawValue ?? -1]
                        )
                        await self.handleAuthFailure()
                        return
                    }
                    AppLogger.ws.warning(
                        "receive loop failed — disconnecting",
                        context: ["error": String(describing: error)]
                    )
                    await self.handleDisconnect()
                    return
                }
            }
        }
    }

    private func receiveOne() async throws -> URLSessionWebSocketTask.Message? {
        guard let task else { return nil }
        return try await task.receive()
    }

    private func currentCloseCode() -> URLSessionWebSocketTask.CloseCode? {
        task?.closeCode
    }

    /// WebSocket close codes that mean "your credentials are no good — don't reconnect".
    /// 1008 (policyViolation) is what the server sends when JWT verification or the
    /// membership check fails; 4001/4003 are private-range codes we reserve for
    /// "token revoked" and "user no longer a member".
    private static func isAuthCloseCode(_ code: URLSessionWebSocketTask.CloseCode?) -> Bool {
        guard let code else { return false }
        switch code {
        case .policyViolation:
            return true
        default:
            // Private-range codes 4000–4999 are carried as raw ints; cross-check.
            let raw = code.rawValue
            return raw == 4001 || raw == 4003
        }
    }

    private func handleIncoming(_ raw: URLSessionWebSocketTask.Message) {
        // A successful receive means we're fully connected again — reset the
        // backoff counter so the next blip starts from 1s, not where we left off.
        reconnectAttempt = 0

        let data: Data
        switch raw {
        case .data(let d):
            data = d
        case .string(let text):
            guard let d = text.data(using: .utf8) else {
                AppLogger.ws.error("inbound string frame not UTF-8", context: ["len": text.count])
                return
            }
            data = d
        @unknown default:
            AppLogger.ws.warning("received unknown WebSocket message kind")
            return
        }

        // Prefer the envelope so we can honor seq-based dedup. Fall back to bare
        // WSServerMessage for legacy/unseq'd messages so older server builds still
        // work during rollout.
        if let envelope = try? decoder.decode(WSServerEnvelope.self, from: data) {
            if let seq = envelope.seq {
                if seq <= lastYieldedSeq {
                    AppLogger.ws.info(
                        "dropping duplicate/out-of-order WS message",
                        context: ["seq": seq, "last": lastYieldedSeq]
                    )
                    return
                }
                lastYieldedSeq = seq
            }
            continuation?.yield(envelope.message)
            return
        }

        do {
            let decoded = try decoder.decode(WSServerMessage.self, from: data)
            continuation?.yield(decoded)
        } catch {
            AppLogger.ws.error(
                "inbound decode failed",
                error: error,
                context: ["bytes": data.count]
            )
        }
    }

    private func handleAuthFailure() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        teardownSocket()
        continuation?.finish()
        continuation = nil
        connectionParams = nil
        state = .disconnected
        Task { @MainActor in
            NotificationCenter.default.post(name: .unpluggedAuthDidInvalidate, object: nil)
        }
    }

    private func handleDisconnect() {
        teardownSocket()
        state = .disconnected

        guard shouldReconnect, reconnectAttempt < Self.maxReconnectAttempts else {
            if shouldReconnect {
                // We wanted to reconnect but burned through every attempt — the
                // session stream ends here. Everything downstream (orchestrator
                // state sync, shield re-engagement) now falls back to polling.
                AppLogger.ws.critical(
                    "reconnect budget exhausted — stream closing",
                    context: ["attempts": reconnectAttempt, "max": Self.maxReconnectAttempts]
                )
            }
            continuation?.finish()
            continuation = nil
            return
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectAttempt += 1
        // 1s, 2s, 4s, 8s, 16s, 30s — capped at maxBackoffSeconds. Jitter (up to
        // 25% of the base delay) keeps a fleet of clients from reconnecting in
        // lockstep after a server blip.
        let base = min(UInt64(1) << (reconnectAttempt - 1), Self.maxBackoffSeconds)
        let jitter = UInt64.random(in: 0...(base * 1_000_000_000 / 4))
        let delayNanos = base * 1_000_000_000 + jitter

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard let self, !Task.isCancelled else { return }
            await self.openSocket()
        }
    }

    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.heartbeatIntervalSeconds * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.sendHeartbeatPing()
            }
        }
    }

    /// Fires an application-level heartbeat message AND a native WebSocket ping.
    /// The native ping's pong handler drives `outstandingHeartbeatPings` back to
    /// zero; if two intervals go by without a pong, we treat the socket as
    /// half-open and force-reconnect (TCP keepalive can take minutes to notice).
    private func sendHeartbeatPing() async {
        guard let task else { return }

        if outstandingHeartbeatPings >= Self.maxOutstandingHeartbeatPings {
            AppLogger.ws.warning(
                "heartbeat stalled — forcing reconnect",
                context: ["outstanding": outstandingHeartbeatPings]
            )
            await handleDisconnect()
            return
        }

        outstandingHeartbeatPings += 1

        task.sendPing { [weak self] error in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                await self.handlePingCompletion(error: error)
            }
        }

        do {
            try await send(.heartbeat)
        } catch {
            AppLogger.ws.warning("heartbeat send failed", context: ["error": String(describing: error)])
            await handleDisconnect()
        }
    }

    private func handlePingCompletion(error: Error?) {
        if let error {
            AppLogger.ws.warning("ping failed", context: ["error": String(describing: error)])
            return
        }
        if outstandingHeartbeatPings > 0 {
            outstandingHeartbeatPings -= 1
        }
    }
}
