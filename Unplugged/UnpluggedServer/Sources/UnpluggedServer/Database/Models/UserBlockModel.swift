//
//  UserBlockModel.swift
//  UnpluggedServer.Database.Models
//

import Fluent
import Vapor

final class UserBlockModel: Model, @unchecked Sendable {
    static let schema = "user_blocks"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "blocker_id")
    var blockerID: UUID

    @Field(key: "blocked_id")
    var blockedID: UUID

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, blockerID: UUID, blockedID: UUID) {
        self.id = id
        self.blockerID = blockerID
        self.blockedID = blockedID
    }
}
