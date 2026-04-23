import Fluent
import Vapor

final class UserReportModel: Model, @unchecked Sendable {
    static let schema = "user_reports"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "reporter_id")
    var reporterID: UUID

    @Field(key: "reported_id")
    var reportedID: UUID

    @Field(key: "reason")
    var reason: String

    @OptionalField(key: "details")
    var details: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, reporterID: UUID, reportedID: UUID, reason: String, details: String? = nil) {
        self.id = id
        self.reporterID = reporterID
        self.reportedID = reportedID
        self.reason = reason
        self.details = details
    }
}
