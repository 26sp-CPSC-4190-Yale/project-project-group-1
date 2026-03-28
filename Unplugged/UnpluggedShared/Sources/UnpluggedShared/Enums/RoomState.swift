//
//  RoomState.swift
//  UnpluggedShared.Enums
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

public enum RoomState: String, Codable, Sendable {
    case idle
    case broadcasting
    case joining
    case countdown
    case locked
    case ending
    case ended
}

