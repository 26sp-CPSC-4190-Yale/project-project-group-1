//
//  WebSocketClient.swift
//  Unplugged.Services.Networking
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import UnpluggedShared

/// Thin wrapper around `URLSessionWebSocketTask` that emits server-side session events
/// as an `AsyncStream<WSServerMessage>`. The auth token is passed as a query param
/// because `URLSessionWebSocketTask` does not allow custom headers to be set cleanly.
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
    private var continuation: AsyncStream<WSServerMessage>.Continuation?
    private(set) var state: ConnectionState = .idle

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
    func connect(sessionID: UUID, token: String) -> AsyncStream<WSServerMessage> {
        disconnect()

        let stream = AsyncStream<WSServerMessage> { continuation in
            self.continuation = continuation
        }

        state = .connecting

        var components = URLComponents(string: Config.webSocketBaseURL)!
        components.path += "/sessions/\(sessionID.uuidString)/ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]

        guard let url = components.url else {
            state = .disconnected
            continuation?.finish()
            continuation = nil
            return stream
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        state = .connected

        startReceiveLoop()
        startHeartbeat()

        return stream
    }

    func send(_ message: WSClientMessage) async throws {
        guard let task else { return }
        let data = try encoder.encode(message)
        try await task.send(.data(data))
    }

    func disconnect() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        continuation?.finish()
        continuation = nil
        state = .disconnected
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
        state = .disconnected
        continuation?.finish()
        continuation = nil
        task = nil
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
