import Foundation
import UnpluggedShared

struct APIClient {
    private let baseURL = Config.baseURL
    private let cache: LocalCacheService

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    init(cache: LocalCacheService) {
        self.cache = cache
    }

    func send<T: Decodable>(_ route: APIRouter) async throws -> T {
        let request = try buildRequest(route)
        let (data, response) = try await performRequest(request, route: route)
        try validate(response, with: data, route: route)
        let decoder = Self.makeDecoder()
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
        let request = try buildRequest(route)
        let (data, response) = try await performRequest(request, route: route)
        try validate(response, with: data, route: route)
    }

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
            throw AppError.serverError
        }
        var request = URLRequest(url: url)
        request.httpMethod = route.method.rawValue
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        if route.requiresAuth, let token = cache.readCachedToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = route.body {
            let encoder = Self.makeEncoder()
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

    private func validate(_ response: URLResponse, with data: Data, route: APIRouter) throws {
        guard let http = response as? HTTPURLResponse else {
            AppLogger.network.error(
                "non-HTTP response returned",
                context: [
                    "path": route.path,
                    "type": String(describing: type(of: response))
                ]
            )
            throw AppError.serverError
        }
        if (200...299).contains(http.statusCode) { return }

        let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["reason"] as? String
        let fallbackMsg = reason ?? "HTTP \(http.statusCode)"

        let level: (String, [String: Any]) -> Void = http.statusCode == 401
            ? { msg, ctx in AppLogger.network.warning(msg, context: ctx) }
            : { msg, ctx in AppLogger.network.error(msg, context: ctx) }

        level(
            "HTTP \(http.statusCode) \(route.method.rawValue) \(route.path)",
            [
                "status": http.statusCode,
                "reason": reason ?? "<none>",
                "preview": Self.previewBody(data)
            ]
        )

        switch http.statusCode {
        case 401:       throw NSError(domain: "Vapor", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: reason ?? "Unauthorized"])
        case 404:       throw NSError(domain: "Vapor", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: reason ?? "Not Found"])
        case 400, 422:  throw NSError(domain: "Vapor", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: reason ?? "Validation Failed"])
        default:        throw NSError(domain: "Vapor", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: fallbackMsg])
        }
    }

    // 256 bytes captures the Vapor reason field without flooding the log ring buffer
    private static func previewBody(_ data: Data, limit: Int = 256) -> String {
        guard !data.isEmpty else { return "<empty>" }
        let clipped = data.prefix(limit)
        let text = String(data: clipped, encoding: .utf8) ?? "<binary \(data.count) bytes>"
        return data.count > limit ? "\(text)…(\(data.count)B)" : text
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }

            let value = try container.decode(String.self)
            if let date = fractional.date(from: value) {
                return date
            }

            if let date = standard.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO-8601 date string"
            )
        }
        return decoder
    }
}

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ value: any Encodable) { _encode = value.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
