//
//  Session.swift
//  UnpluggedShared.Models
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

public struct Session: Codable, Identifiable, Sendable {
    public let id: UUID
    public let code: String
    public let hostID: UUID
    public let state: RoomState
    public let startedAt: Date?
    public let endedAt: Date?
    public let title: String
    public let timeLimitMinutes: Int

    public init(id: UUID, code: String, hostID: UUID, state: RoomState, startedAt: Date?, endedAt: Date?, title: String, timeLimitMinutes: Int) {
        self.id = id
        self.code = code
        self.hostID = hostID
        self.state = state
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.timeLimitMinutes = timeLimitMinutes
    }
}

