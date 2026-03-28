//
//  GroupMemberModel.swift
//  UnpluggedServer.Database.Models
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
import Vapor

final class GroupMemberModel: Model, @unchecked Sendable {
    static let schema = "group_members"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "group_id")
    var groupID: UUID

    @Field(key: "user_id")
    var userID: UUID

    @Field(key: "joined_at")
    var joinedAt: Date

    init() {}

    init(id: UUID? = nil, groupID: UUID, userID: UUID) {
        self.id = id
        self.groupID = groupID
        self.userID = userID
        self.joinedAt = Date()
    }
}
