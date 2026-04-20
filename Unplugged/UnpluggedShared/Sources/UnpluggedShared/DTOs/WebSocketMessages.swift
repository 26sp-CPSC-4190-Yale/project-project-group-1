//
//  WebSocketMessages.swift
//  UnpluggedShared.DTOs
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

public enum WSServerMessage: Codable, Sendable {
    case participantJoined(ParticipantResponse)
    case participantLeft(userID: UUID)
    case sessionStarted(endsAt: Date)
    case sessionLocked(endsAt: Date)
    case sessionEnded
    case stateSync(SessionResponse)
    case jailbreakReported(userID: UUID, reason: String)
    case error(message: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum MessageType: String, Codable {
        case participantJoined
        case participantLeft
        case sessionStarted
        case sessionLocked
        case sessionEnded
        case stateSync
        case jailbreakReported
        case error
    }

    private struct ParticipantLeftPayload: Codable { let userID: UUID }
    private struct EndsAtPayload: Codable { let endsAt: Date }
    private struct JailbreakPayload: Codable { let userID: UUID; let reason: String }
    private struct ErrorPayload: Codable { let message: String }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .participantJoined(let p):
            try container.encode(MessageType.participantJoined, forKey: .type)
            try container.encode(p, forKey: .payload)
        case .participantLeft(let userID):
            try container.encode(MessageType.participantLeft, forKey: .type)
            try container.encode(ParticipantLeftPayload(userID: userID), forKey: .payload)
        case .sessionStarted(let endsAt):
            try container.encode(MessageType.sessionStarted, forKey: .type)
            try container.encode(EndsAtPayload(endsAt: endsAt), forKey: .payload)
        case .sessionLocked(let endsAt):
            try container.encode(MessageType.sessionLocked, forKey: .type)
            try container.encode(EndsAtPayload(endsAt: endsAt), forKey: .payload)
        case .sessionEnded:
            try container.encode(MessageType.sessionEnded, forKey: .type)
        case .stateSync(let response):
            try container.encode(MessageType.stateSync, forKey: .type)
            try container.encode(response, forKey: .payload)
        case .jailbreakReported(let userID, let reason):
            try container.encode(MessageType.jailbreakReported, forKey: .type)
            try container.encode(JailbreakPayload(userID: userID, reason: reason), forKey: .payload)
        case .error(let message):
            try container.encode(MessageType.error, forKey: .type)
            try container.encode(ErrorPayload(message: message), forKey: .payload)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        switch type {
        case .participantJoined:
            self = .participantJoined(try container.decode(ParticipantResponse.self, forKey: .payload))
        case .participantLeft:
            let p = try container.decode(ParticipantLeftPayload.self, forKey: .payload)
            self = .participantLeft(userID: p.userID)
        case .sessionStarted:
            let p = try container.decode(EndsAtPayload.self, forKey: .payload)
            self = .sessionStarted(endsAt: p.endsAt)
        case .sessionLocked:
            let p = try container.decode(EndsAtPayload.self, forKey: .payload)
            self = .sessionLocked(endsAt: p.endsAt)
        case .sessionEnded:
            self = .sessionEnded
        case .stateSync:
            self = .stateSync(try container.decode(SessionResponse.self, forKey: .payload))
        case .jailbreakReported:
            let p = try container.decode(JailbreakPayload.self, forKey: .payload)
            self = .jailbreakReported(userID: p.userID, reason: p.reason)
        case .error:
            let p = try container.decode(ErrorPayload.self, forKey: .payload)
            self = .error(message: p.message)
        }
    }
}

public enum WSClientMessage: Codable, Sendable {
    case hello(token: String)
    case heartbeat
    case reportJailbreak(reason: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum MessageType: String, Codable {
        case hello
        case heartbeat
        case reportJailbreak
    }

    private struct TokenPayload: Codable { let token: String }
    private struct ReasonPayload: Codable { let reason: String }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let token):
            try container.encode(MessageType.hello, forKey: .type)
            try container.encode(TokenPayload(token: token), forKey: .payload)
        case .heartbeat:
            try container.encode(MessageType.heartbeat, forKey: .type)
        case .reportJailbreak(let reason):
            try container.encode(MessageType.reportJailbreak, forKey: .type)
            try container.encode(ReasonPayload(reason: reason), forKey: .payload)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        switch type {
        case .hello:
            let p = try container.decode(TokenPayload.self, forKey: .payload)
            self = .hello(token: p.token)
        case .heartbeat:
            self = .heartbeat
        case .reportJailbreak:
            let p = try container.decode(ReasonPayload.self, forKey: .payload)
            self = .reportJailbreak(reason: p.reason)
        }
    }
}
