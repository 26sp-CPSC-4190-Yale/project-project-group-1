import Fluent
import Foundation

final class OAuthIdentityModel: Model, @unchecked Sendable {
    static let schema = "oauth_identities"

    static let appleProvider = "apple"
    static let googleProvider = "google"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: UserModel

    @Field(key: "provider")
    var provider: String

    @Field(key: "subject")
    var subject: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(userID: UUID, provider: String, subject: String) {
        self.$user.id = userID
        self.provider = provider
        self.subject = subject
    }
}
