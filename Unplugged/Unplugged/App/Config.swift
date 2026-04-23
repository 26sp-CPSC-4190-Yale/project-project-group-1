
enum Config {
    // change if deploying to production
    nonisolated static let baseURL = "https://unplugged.name"

    nonisolated static var webSocketBaseURL: String {
        if baseURL.hasPrefix("https://") {
            return "wss://" + baseURL.dropFirst("https://".count)
        } else if baseURL.hasPrefix("http://") {
            return "ws://" + baseURL.dropFirst("http://".count)
        }
        return baseURL
    }
}
