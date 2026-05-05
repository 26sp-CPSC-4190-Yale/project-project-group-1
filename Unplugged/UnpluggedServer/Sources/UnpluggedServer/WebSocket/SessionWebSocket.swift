import Foundation
import UnpluggedShared
import Vapor

actor SessionHub {
    // sessionID to userID to WebSocket
    private var connections: [UUID: [UUID: WebSocket]] = [:]

    func join(sessionID: UUID, userID: UUID, ws: WebSocket) {
        var session = connections[sessionID] ?? [:]
        session[userID] = ws
        connections[sessionID] = session
    }

    func leave(sessionID: UUID, userID: UUID) {
        guard var session = connections[sessionID] else { return }
        session.removeValue(forKey: userID)
        if session.isEmpty {
            connections.removeValue(forKey: sessionID)
        } else {
            connections[sessionID] = session
        }
    }

    func broadcast(sessionID: UUID, message: WSServerMessage) async {
        guard let session = connections[sessionID], !session.isEmpty else { return }
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(message)
        } catch {
            return
        }
        guard let text = String(data: data, encoding: .utf8) else { return }
        for (_, ws) in session {
            try? await ws.send(text)
        }
    }

    func send(sessionID: UUID, toUserID userID: UUID, message: WSServerMessage) async {
        guard let ws = connections[sessionID]?[userID] else { return }
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(message)
        } catch {
            return
        }
        guard let text = String(data: data, encoding: .utf8) else { return }
        try? await ws.send(text)
    }
}

private struct SessionHubKey: StorageKey {
    typealias Value = SessionHub
}

extension Application {
    var sessionHub: SessionHub {
        if let existing = storage[SessionHubKey.self] {
            return existing
        }
        let hub = SessionHub()
        storage[SessionHubKey.self] = hub
        return hub
    }
}

extension Request {
    var sessionHub: SessionHub {
        application.sessionHub
    }
}
