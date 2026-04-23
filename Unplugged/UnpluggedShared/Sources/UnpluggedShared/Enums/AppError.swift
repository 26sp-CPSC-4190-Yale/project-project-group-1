public enum AppError: String, Codable, Sendable, Error {
    case unauthorized
    case notFound
    case validationFailed
    case serverError
    case sessionFull
    case sessionNotActive
}

