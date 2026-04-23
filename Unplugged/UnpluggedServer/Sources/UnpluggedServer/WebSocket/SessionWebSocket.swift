//
//  SessionWebSocket.swift
//  UnpluggedServer.WebSocket
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import NIOWebSocket
import UnpluggedShared
import Vapor

/// Tracks live WebSocket connections per room, stamps outbound messages with a
/// monotonic per-room sequence number (so clients can dedup replays on
/// reconnect), and can forcibly evict a member whose membership has been
/// revoked.
///
/// Eviction (`kick`) is how we keep P1-4 honest: if a participant is removed
/// from a room (they called `/leave`, or their account was deleted), we close
/// their socket immediately with a policy-class code so they stop receiving
/// broadcasts. The client treats policyViolation as "don't reconnect" and
/// routes back to sign-in / idle.
actor SessionHub {
    /// roomID -> (userID -> WebSocket)
    private var connections: [UUID: [UUID: WebSocket]] = [:]
    /// roomID -> monotonic seq counter for outbound envelopes
    private var roomSeq: [UUID: UInt64] = [:]

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
            roomSeq.removeValue(forKey: roomID)
        } else {
            connections[roomID] = room
        }
    }

    /// Forcibly close and evict a member's socket with the given close code.
    /// Called when a user leaves / is blocked / is deleted so their client
    /// can't keep receiving in-flight broadcasts from a room they no longer
    /// belong to.
    func kick(roomID: UUID, userID: UUID, code: WebSocketErrorCode = .policyViolation) async {
        guard let ws = connections[roomID]?[userID] else { return }
        try? await ws.close(code: code)
        leave(roomID: roomID, userID: userID)
    }

    /// Returns true if the user currently has an active socket for this room.
    /// Used by the inbound handler to decide whether to process an incoming
    /// message from a client whose membership may have been revoked.
    func isMember(roomID: UUID, userID: UUID) -> Bool {
        connections[roomID]?[userID] != nil
    }

    func broadcast(roomID: UUID, message: WSServerMessage) async {
        guard let room = connections[roomID], !room.isEmpty else { return }
        let seq = nextSeq(for: roomID)
        let envelope = WSServerEnvelope(seq: seq, message: message)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard
            let data = try? encoder.encode(envelope),
            let text = String(data: data, encoding: .utf8)
        else { return }
        for (_, ws) in room {
            try? await ws.send(text)
        }
    }

    func send(roomID: UUID, toUserID userID: UUID, message: WSServerMessage) async {
        guard let ws = connections[roomID]?[userID] else { return }
        let seq = nextSeq(for: roomID)
        let envelope = WSServerEnvelope(seq: seq, message: message)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard
            let data = try? encoder.encode(envelope),
            let text = String(data: data, encoding: .utf8)
        else { return }
        try? await ws.send(text)
    }

    private func nextSeq(for roomID: UUID) -> UInt64 {
        let next = (roomSeq[roomID] ?? 0) &+ 1
        roomSeq[roomID] = next
        return next
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
