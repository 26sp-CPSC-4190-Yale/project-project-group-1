// §13 known limitation, counts live per-process, multi-replica deployment gives each replica its own counters, Redis is the follow-up
import Vapor

actor RateLimiter {
    private var buckets: [String: (count: Int, windowStart: Date)] = [:]

    func allow(key: String, limit: Int, window: TimeInterval) -> Bool {
        let now = Date()
        if let b = buckets[key], now.timeIntervalSince(b.windowStart) <= window {
            if b.count >= limit { return false }
            buckets[key] = (b.count + 1, b.windowStart)
            return true
        }
        buckets[key] = (1, now)
        return true
    }
}

struct RateLimitMiddleware: AsyncMiddleware {
    let limiter: RateLimiter
    let limit: Int
    let window: TimeInterval
    // keys are prefixed with scope so different route groups do not share a bucket
    let scope: String

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let ip = request.remoteAddress?.ipAddress ?? "unknown"
        let key = "\(scope):ip:\(ip)"
        guard await limiter.allow(key: key, limit: limit, window: window) else {
            throw Abort(.tooManyRequests, reason: "Too many requests. Try again in a minute.")
        }
        return try await next.respond(to: request)
    }
}

enum RateLimit {
    static let shared = RateLimiter()

    // 10 per minute slows credential stuffing's hundreds-of-tries rate without punishing a mistyped password
    static var login: RateLimitMiddleware {
        .init(limiter: shared, limit: 10, window: 60, scope: "auth-login")
    }

    // 5 per hour, real users register once, higher rates are account farming or scripted signup abuse
    static var register: RateLimitMiddleware {
        .init(limiter: shared, limit: 5, window: 60 * 60, scope: "auth-register")
    }

    // provider-side abuse protection exists but we still cap to protect our JWT verify path from hammering
    static var oauth: RateLimitMiddleware {
        .init(limiter: shared, limit: 20, window: 60, scope: "auth-oauth")
    }
}

extension RateLimiter {
    // username-scoped bucket catches credential stuffing that rotates IPs but targets one account
    func allowUsername(_ username: String) -> Bool {
        allow(
            key: "login-user:\(username.lowercased())",
            limit: 10,
            window: 60
        )
    }
}
