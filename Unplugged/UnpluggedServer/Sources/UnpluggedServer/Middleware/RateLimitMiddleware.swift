//
//  RateLimitMiddleware.swift
//  UnpluggedServer.Middleware
//
//  Per-route, in-memory token-bucket-style rate limiter.
//
//  Known limitations documented in §13: counts live in the process, so a multi-replica
//  deployment gives each replica its own counters. For a single-node MVP this is
//  acceptable; moving to Redis is a follow-up. What this *does* prevent right now is
//  casual credential stuffing and automated signup abuse from a single attacker IP.
//

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

/// Generic IP-based rate limiter. Use `.auth(...)` helpers to apply to auth routes.
struct RateLimitMiddleware: AsyncMiddleware {
    let limiter: RateLimiter
    let limit: Int
    let window: TimeInterval
    /// Differentiator so two different route groups don't share a bucket.
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

/// Shared limiter instance so different middlewares can cooperate if we later want
/// per-username throttling on login. Holding it at app level keeps the actor reachable
/// from controllers that want to check usernames directly.
enum RateLimit {
    static let shared = RateLimiter()

    /// 10 login attempts per minute per IP. Credential stuffing typically tries
    /// hundreds of combinations; 10/min makes the attack rate-limited to slow that
    /// bulk iteration without punishing a user who mistypes a few times.
    static var login: RateLimitMiddleware {
        .init(limiter: shared, limit: 10, window: 60, scope: "auth-login")
    }

    /// 5 registrations per hour per IP. Real users register once; anything more is
    /// likely account-farming or scripted signup abuse.
    static var register: RateLimitMiddleware {
        .init(limiter: shared, limit: 5, window: 60 * 60, scope: "auth-register")
    }

    /// OAuth has its own provider-side abuse protection but we still cap by IP to
    /// prevent someone from hammering our JWT verify path.
    static var oauth: RateLimitMiddleware {
        .init(limiter: shared, limit: 20, window: 60, scope: "auth-oauth")
    }
}

extension RateLimiter {
    /// Separate helper: check a username-scoped login bucket. Called from the login
    /// handler so we also rate-limit individual accounts (credential stuffing that
    /// rotates IPs but targets one user).
    func allowUsername(_ username: String) -> Bool {
        allow(
            key: "login-user:\(username.lowercased())",
            limit: 10,
            window: 60
        )
    }
}
