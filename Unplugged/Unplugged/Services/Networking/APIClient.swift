//
//  APIClient.swift
//  Unplugged.Services.Networking
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import UnpluggedShared

/// Typed error thrown by `APIClient`. Carries both a coarse `AppError` kind for
/// pattern matching and the server's `reason` string for display. Conforms to
/// `LocalizedError` so callers that surface `.localizedDescription` directly
/// (legacy AuthViewModel path) still show a useful message.
struct APIError: Error, LocalizedError {
    let kind: AppError
    let status: Int?
    let reason: String?
    let retryAfter: TimeInterval?

    init(kind: AppError, status: Int? = nil, reason: String? = nil, retryAfter: TimeInterval? = nil) {
        self.kind = kind
        self.status = status
        self.reason = reason
        self.retryAfter = retryAfter
    }

    var errorDescription: String? { reason }
}

/// Posted when the client learns the current auth token is no longer valid
/// (HTTP 401 or WebSocket auth-class close). `AuthViewModel` listens for this
/// and drops the user back to the sign-in screen.
extension Notification.Name {
    static let unpluggedAuthDidInvalidate = Notification.Name("unplugged.auth.didInvalidate")
}

struct APIClient {
    private let baseURL = Config.baseURL
    private let cache: LocalCacheService

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // Tight per-request timeout catches stalled requests before the user
        // notices; generous resource timeout allows a slow network (3G/handoff)
        // to finish a legitimately slow POST.
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    init(cache: LocalCacheService) {
        self.cache = cache
    }

    func send<T: Decodable>(_ route: APIRouter) async throws -> T {
        let (data, _) = try await performWithRetry(route)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            AppLogger.network.error(
                "decode failed for \(String(describing: T.self))",
                error: error,
                context: [
                    "path": route.path,
                    "bytes": data.count,
                    "preview": Self.previewBody(data)
                ]
            )
            throw error
        }
    }

    func sendVoid(_ route: APIRouter) async throws {
        _ = try await performWithRetry(route)
    }

    // MARK: - Retry loop

    /// Retry plan:
    ///   - URLError (timeout, DNS, connection lost) → up to 3 attempts with
    ///     exponential backoff (200 ms, 400 ms, 800 ms) + 25% jitter.
    ///   - 5xx and 503 → retried on the same schedule.
    ///   - 429 → honored by parsing `Retry-After`; still bounded by max attempts.
    ///   - 4xx (except 408, 429) → not retried; these are deterministic.
    /// Non-idempotent writes (POST/PATCH/DELETE) are retried only when we got no
    /// response at all — once the server has acked something we do not replay.
    private func performWithRetry(_ route: APIRouter) async throws -> (Data, HTTPURLResponse) {
        let maxAttempts = 3
        var attempt = 0
        var lastError: Error = APIError(kind: .network, reason: "retry loop exited without attempt")

        while attempt < maxAttempts {
            attempt += 1
            do {
                let request = try buildRequest(route)
                let (data, response) = try await performRequest(request, route: route)
                let http = try httpResponse(response, route: route)
                if (200...299).contains(http.statusCode) {
                    return (data, http)
                }
                let apiError = try mapFailure(status: http.statusCode, data: data, route: route)

                // 429 gets its Retry-After honored. 5xx gets a backoff retry on
                // idempotent methods; non-idempotent methods do not retry past
                // a server-acked failure.
                let retriable = isRetriableStatus(http.statusCode, route: route)
                if retriable, attempt < maxAttempts {
                    let delay = Self.backoffDelay(attempt: attempt, retryAfter: apiError.retryAfter)
                    try await Task.sleep(nanoseconds: delay)
                    lastError = apiError
                    continue
                }
                throw apiError
            } catch let urlError as URLError {
                // Cancellation is not a retriable condition — a user-dismissed
                // screen cancelling its task should bail immediately.
                if urlError.code == .cancelled { throw urlError }

                lastError = urlError
                if attempt < maxAttempts, isRetriableTransport(urlError, route: route) {
                    let delay = Self.backoffDelay(attempt: attempt, retryAfter: nil)
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }
                throw APIError(kind: .network, status: nil, reason: urlError.localizedDescription)
            }
        }

        throw lastError
    }

    private func isRetriableStatus(_ status: Int, route: APIRouter) -> Bool {
        switch status {
        case 408, 429: return true
        case 500...599: return route.method == .get
        default: return false
        }
    }

    private func isRetriableTransport(_ error: URLError, route: APIRouter) -> Bool {
        switch error.code {
        case .timedOut,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .httpTooManyRedirects:
            // For non-idempotent methods, retry only if we can prove the
            // request never reached the server. `.networkConnectionLost`
            // after sending is ambiguous — don't replay a POST and risk
            // double-creating a room.
            if route.method == .get { return true }
            return error.code != .networkConnectionLost
        default:
            return false
        }
    }

    private static func backoffDelay(attempt: Int, retryAfter: TimeInterval?) -> UInt64 {
        if let retryAfter, retryAfter > 0 {
            let capped = min(retryAfter, 10)
            return UInt64(capped * 1_000_000_000)
        }
        // 200 ms, 400 ms, 800 ms …
        let base = UInt64(200_000_000) * UInt64(1 << (attempt - 1))
        let jitter = UInt64.random(in: 0...(base / 4))
        return base + jitter
    }

    // MARK: - Transport

    private func performRequest(_ request: URLRequest, route: APIRouter) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            AppLogger.network.error(
                "URLSession failed \(route.method.rawValue) \(route.path)",
                error: urlError,
                context: [
                    "urlerror_code": urlError.errorCode,
                    "timed_out": urlError.code == .timedOut,
                    "no_internet": urlError.code == .notConnectedToInternet,
                    "cancelled": urlError.code == .cancelled
                ]
            )
            throw urlError
        } catch {
            AppLogger.network.error(
                "transport failed \(route.method.rawValue) \(route.path)",
                error: error
            )
            throw error
        }
    }

    private func buildRequest(_ route: APIRouter) throws -> URLRequest {
        guard let url = URL(string: baseURL + route.path) else {
            AppLogger.network.critical(
                "invalid URL for route",
                context: ["base": baseURL, "path": route.path]
            )
            throw APIError(kind: .serverError, reason: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = route.method.rawValue
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if route.requiresAuth, let token = cache.readCachedToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = route.body {
            do {
                request.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                AppLogger.network.error(
                    "request body encode failed",
                    error: error,
                    context: ["path": route.path]
                )
                throw error
            }
        }

        return request
    }

    private func httpResponse(_ response: URLResponse, route: APIRouter) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            AppLogger.network.error(
                "non-HTTP response returned",
                context: [
                    "path": route.path,
                    "type": String(describing: type(of: response))
                ]
            )
            throw APIError(kind: .serverError, reason: "Invalid response")
        }
        return http
    }

    /// Map a non-2xx response to an `APIError`. On 401 we also invalidate the
    /// cached token and post `unpluggedAuthDidInvalidate` so the auth layer can
    /// push the user back to the sign-in screen; retrying with a known-bad
    /// token would just yield another 401 and waste user time.
    private func mapFailure(status: Int, data: Data, route: APIRouter) throws -> APIError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let reason = json?["reason"] as? String

        let level: (String, [String: Any]) -> Void = status == 401
            ? { msg, ctx in AppLogger.network.warning(msg, context: ctx) }
            : { msg, ctx in AppLogger.network.error(msg, context: ctx) }

        level(
            "HTTP \(status) \(route.method.rawValue) \(route.path)",
            [
                "status": status,
                "reason": reason ?? "<none>",
                "preview": Self.previewBody(data)
            ]
        )

        switch status {
        case 401:
            // Drop the cached token now — future requests should not attach it.
            // Fire the auth-invalidated notification on MainActor so UI listeners
            // (AuthViewModel) can transition synchronously without races.
            cache.deleteToken()
            Task { @MainActor in
                NotificationCenter.default.post(name: .unpluggedAuthDidInvalidate, object: nil)
            }
            return APIError(kind: .unauthorized, status: status, reason: reason ?? "Unauthorized")
        case 404:
            return APIError(kind: .notFound, status: status, reason: reason ?? "Not Found")
        case 400, 422:
            return APIError(kind: .validationFailed, status: status, reason: reason ?? "Validation Failed")
        case 429:
            // Retry-After can be a number of seconds or an HTTP-date; we only
            // parse the integer form. Headers are not reliably surfaced at this
            // layer (no HTTPURLResponse pass-through), so attempt to read it
            // from the JSON body first.
            let retryAfter = (json?["retryAfter"] as? TimeInterval) ?? (json?["retry_after"] as? TimeInterval)
            return APIError(kind: .rateLimited, status: status, reason: reason ?? "Rate Limited", retryAfter: retryAfter)
        case 500...599:
            return APIError(kind: .serverError, status: status, reason: reason ?? "Server error")
        default:
            return APIError(kind: .serverError, status: status, reason: reason ?? "HTTP \(status)")
        }
    }

    /// Clip response bodies for logging — large payloads blow up the log
    /// ring buffer and slow down Console.app. 256 bytes is enough to see the
    /// "reason" field for Vapor errors.
    private static func previewBody(_ data: Data, limit: Int = 256) -> String {
        guard !data.isEmpty else { return "<empty>" }
        let clipped = data.prefix(limit)
        let text = String(data: clipped, encoding: .utf8) ?? "<binary \(data.count) bytes>"
        return data.count > limit ? "\(text)…(\(data.count)B)" : text
    }
}

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ value: any Encodable) { _encode = value.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
