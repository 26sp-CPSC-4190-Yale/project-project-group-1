//
//  UserModel.swift
//  UnpluggedServer.Database.Models
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
import Vapor

final class UserModel: Model, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "username")
    var username: String

    @Field(key: "password_hash")
    var passwordHash: String

    @Field(key: "points")
    var points: Int

    @Siblings(through: UserMedalPivot.self, from: \.$user, to: \.$medal)
    var medals: [MedalModel]

    @OptionalField(key: "device_token") // for push notifs
    var deviceToken: String?

    @OptionalField(key: "last_seen_at")
    var lastSeenAt: Date?

    @OptionalField(key: "apple_subject")
    var appleSubject: String?

    @OptionalField(key: "google_subject")
    var googleSubject: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, username: String, passwordHash: String) {
        self.id = id
        self.username = username
        self.passwordHash = passwordHash
        self.points = 0
    }
}
