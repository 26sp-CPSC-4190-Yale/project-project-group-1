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

        openSocket()
        return stream
    }

    func send(_ message: WSClientMessage) async throws {
        guard let task else { return }
        let data = try encoder.encode(message)
        try await task.send(.data(data))
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
        guard let params = connectionParams else { return }
        state = .connecting

        var components = URLComponents(string: Config.webSocketBaseURL)!
        components.path += "/sessions/\(params.sessionID.uuidString)/ws"

        guard let url = components.url else {
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
        // A successful receive means we're fully connected again — reset the
        // backoff counter so the next blip starts from 1s, not where we left off.
        reconnectAttempt = 0

        switch raw {
        case .data(let data):
            if let decoded = try? decoder.decode(WSServerMessage.self, from: data) {
                continuation?.yield(decoded)
            }
        case .string(let text):
            if let data = text.data(using: .utf8),
               let decoded = try? decoder.decode(WSServerMessage.self, from: data) {
                continuation?.yield(decoded)
            }
        @unknown default:
            break
        }
    }

    private func handleDisconnect() {
        teardownSocket()
        state = .disconnected

        guard shouldReconnect, reconnectAttempt < Self.maxReconnectAttempts else {
            continuation?.finish()
            continuation = nil
            return
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectAttempt += 1
        // 1s, 2s, 4s, 8s, 16s, 30s — capped at maxBackoffSeconds. Jitter (0–25%)
        // keeps a fleet of clients from reconnecting in lockstep after a server blip.
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
                try? await self.send(.heartbeat)
            }
        }
    }
}
