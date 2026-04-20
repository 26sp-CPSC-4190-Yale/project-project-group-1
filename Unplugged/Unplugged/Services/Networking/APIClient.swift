//
//  APIClient.swift
//  Unplugged.Services.Networking
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import UnpluggedShared

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
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    init(cache: LocalCacheService) {
        self.cache = cache
    }

    func send<T: Decodable>(_ route: APIRouter) async throws -> T {
        let request = try buildRequest(route)
        let (data, response) = try await session.data(for: request)
        try validate(response, with: data)
        return try decoder.decode(T.self, from: data)
    }

    func sendVoid(_ route: APIRouter) async throws {
        let request = try buildRequest(route)
        let (data, response) = try await session.data(for: request)
        try validate(response, with: data)
    }

    private func buildRequest(_ route: APIRouter) throws -> URLRequest {
        guard let url = URL(string: baseURL + route.path) else {
            throw AppError.serverError
        }
        var request = URLRequest(url: url)
        request.httpMethod = route.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if route.requiresAuth, let token = cache.readToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = route.body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return request
    }

    private func validate(_ response: URLResponse, with data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw AppError.serverError }
        if (200...299).contains(http.statusCode) { return }

        // Vapor includes "reason" in its JSON error responses
        let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["reason"] as? String
        let fallbackMsg = reason ?? "HTTP \(http.statusCode)"

        switch http.statusCode {
        case 401:       throw NSError(domain: "Vapor", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: reason ?? "Unauthorized"])
        case 404:       throw NSError(domain: "Vapor", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: reason ?? "Not Found"])
        case 400, 422:  throw NSError(domain: "Vapor", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: reason ?? "Validation Failed"])
        default:        throw NSError(domain: "Vapor", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: fallbackMsg])
        }
    }
}

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ value: any Encodable) { _encode = value.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
