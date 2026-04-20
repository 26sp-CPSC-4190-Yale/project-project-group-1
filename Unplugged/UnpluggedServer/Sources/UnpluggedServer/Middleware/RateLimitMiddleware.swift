//
//  RateLimitMiddleware.swift
//  UnpluggedServer.Middleware
//
//  Created by Sebastian Gonzalez on 3/12/26.
//
import Vapor

actor RateLimiter {
    private var requestCounts: [String: (count: Int, lastReset: Date)] = [:]
    private let maxRequests = 100
    private let timeWindow: TimeInterval = 60

    func checkRateLimit(key: String) -> Bool {
        let now = Date()
        if let record = requestCounts[key] {
            if now.timeIntervalSince(record.lastReset) > timeWindow {
                requestCounts[key] = (1, now)
                return true
            } else if record.count < maxRequests {
                requestCounts[key] = (record.count + 1, record.lastReset)
                return true
            } else {
                return false
            }
        } else {
            requestCounts[key] = (1, now)
            return true
        }
    }
}

struct RateLimitMiddleware: AsyncMiddleware {
    let rateLimiter = RateLimiter()
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let key = request.remoteAddress?.ipAddress ?? "unknown"
        let allow = await rateLimiter.checkRateLimit(key: key)
        
        guard allow else {
            throw Abort(.tooManyRequests, reason: "Rate limit exceeded. Please try again later.")
        }
        
        return try await next.respond(to: request)
    }
}
