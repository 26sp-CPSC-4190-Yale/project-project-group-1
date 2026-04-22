
enum Config {
    // Change if deploying to production
    static let baseURL = "https://unplugged.name"

    /// WebSocket base URL derived from `baseURL`, swapping http(s) for ws(s).
    static var webSocketBaseURL: String {
        if baseURL.hasPrefix("https://") {
            return "wss://" + baseURL.dropFirst("https://".count)
        } else if baseURL.hasPrefix("http://") {
            return "ws://" + baseURL.dropFirst("http://".count)
        }
        return baseURL
    }
}
