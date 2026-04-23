import Fluent
import Vapor

final class MedalModel: Model, @unchecked Sendable {
    static let schema = "medals"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "description")
    var description: String

    @Field(key: "icon")
    var icon: String

    @Siblings(through: UserMedalPivot.self, from: \.$medal, to: \.$user)
    var users: [UserModel]

    init() {}

    init(id: UUID? = nil, name: String, description: String, icon: String) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
    }
}

extension MedalModel: Content {}