public enum RoomState: String, Codable, Sendable {
    case idle
    case broadcasting
    case joining
    case countdown
    case locked
    case ending
    case ended
}

