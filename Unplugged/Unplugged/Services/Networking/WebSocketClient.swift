import Foundation
import UnpluggedShared

// auth goes in the Bearer header, query-string auth leaks into access logs and proxy caches
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

    private static let maxReconnectAttempts = 6
    private static let maxBackoffSeconds: UInt64 = 30

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
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
    }

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    guard let message = try await self.receiveOne() else { return }
                    await self.handleIncoming(message)
                } catch {
                    AppLogger.ws.warning("receive loop failed — disconnecting", context: ["error": String(describing: error)])
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

    private func handleIncoming(_ raw: URLSessionWebSocketTask.Message) {
        // reset backoff on successful receive so the next blip starts from 1s
        reconnectAttempt = 0

        switch raw {
        case .data(let data):
            do {
                let decoded = try decoder.decode(WSServerMessage.self, from: data)
                continuation?.yield(decoded)
            } catch {
                AppLogger.ws.error(
                    "inbound decode failed (data frame)",
                    error: error,
                    context: ["bytes": data.count]
                )
            }
        case .string(let text):
            guard let data = text.data(using: .utf8) else {
                AppLogger.ws.error("inbound string frame not UTF-8", context: ["len": text.count])
                return
            }
            do {
                let decoded = try decoder.decode(WSServerMessage.self, from: data)
                continuation?.yield(decoded)
            } catch {
                AppLogger.ws.error(
                    "inbound decode failed (string frame)",
                    error: error,
                    context: ["bytes": data.count]
                )
            }
        @unknown default:
            AppLogger.ws.warning("received unknown WebSocket message kind")
        }
    }

    private func handleDisconnect() {
        teardownSocket()
        state = .disconnected

        guard shouldReconnect, reconnectAttempt < Self.maxReconnectAttempts else {
            if shouldReconnect {
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
        // jitter (0-25%) prevents fleet-wide reconnect lockstep after a server blip
        let base = min(UInt64(1) << (reconnectAttempt - 1), Self.maxBackoffSeconds)
        let jitter = UInt64.random(in: 0...(base * 250_000_000))
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
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self else { return }
                do {
                    try await self.send(.heartbeat)
                } catch {
                    // heartbeat failure is the earliest half-open signal, return and let the receive loop trigger reconnect
                    AppLogger.ws.warning("heartbeat send failed", context: ["error": String(describing: error)])
                    return
                }
            }
        }
    }
}
