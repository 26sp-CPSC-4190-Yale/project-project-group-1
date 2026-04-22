//
//  JailbreakModel.swift
//  UnpluggedServer.Database.Models
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
import Vapor

final class JailbreakModel: Model, @unchecked Sendable {
    static let schema = "jailbreaks"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "session_id")
    var sessionID: UUID

    @Field(key: "user_id")
    var userID: UUID

    @Field(key: "detected_at")
    var detectedAt: Date

    @OptionalField(key: "reason")
    var reason: String?

    init() {}

    init(id: UUID? = nil, sessionID: UUID, userID: UUID, reason: String? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.userID = userID
        self.detectedAt = Date()
        self.reason = reason
    }
}
