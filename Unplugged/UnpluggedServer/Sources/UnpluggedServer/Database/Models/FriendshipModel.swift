//
//  FriendshipModel.swift
//  UnpluggedServer.Database.Models
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
import Vapor

final class FriendshipModel: Model, @unchecked Sendable {
    static let schema = "friendships"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_1_id")
    var user1ID: UUID

    @Field(key: "user_2_id")
    var user2ID: UUID

    @Field(key: "status")
    var status: String  // "pending" or "accepted"

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, user1ID: UUID, user2ID: UUID, status: String = "pending") {
        self.id = id
        self.user1ID = user1ID
        self.user2ID = user2ID
        self.status = status
    }
}
