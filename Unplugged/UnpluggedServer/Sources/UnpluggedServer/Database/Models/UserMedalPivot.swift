import Fluent
import Foundation

final class UserMedalPivot: Model, @unchecked Sendable {
    static let schema = "user_medal_pivot"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: UserModel

    @Parent(key: "medal_id")
    var medal: MedalModel

    @Timestamp(key: "earned_at", on: .create)
    var earnedAt: Date?

    init() {}

    init(userID: UUID, medalID: UUID) {
        self.$user.id = userID
        self.$medal.id = medalID
    }
}