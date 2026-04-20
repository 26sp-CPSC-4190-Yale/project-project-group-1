//
//  SessionWebSocket.swift
//  UnpluggedServer.WebSocket
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import UnpluggedShared
import Vapor

/// Tracks live WebSocket connections per room and broadcasts server events.
actor SessionHub {
    /// roomID -> (userID -> WebSocket)
    private var connections: [UUID: [UUID: WebSocket]] = [:]

    func join(roomID: UUID, userID: UUID, ws: WebSocket) {
        var room = connections[roomID] ?? [:]
        room[userID] = ws
        connections[roomID] = room
    }

    func leave(roomID: UUID, userID: UUID) {
        guard var room = connections[roomID] else { return }
        room.removeValue(forKey: userID)
        if room.isEmpty {
            connections.removeValue(forKey: roomID)
        } else {
            connections[roomID] = room
        }
    }

    func broadcast(roomID: UUID, message: WSServerMessage) async {
        guard let room = connections[roomID], !room.isEmpty else { return }
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(message)
        } catch {
            return
        }
        guard let text = String(data: data, encoding: .utf8) else { return }
        for (_, ws) in room {
            try? await ws.send(text)
        }
    }

    func send(roomID: UUID, toUserID userID: UUID, message: WSServerMessage) async {
        guard let ws = connections[roomID]?[userID] else { return }
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
