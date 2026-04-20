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
        try validate(response)
        return try decoder.decode(T.self, from: data)
    }

    func sendVoid(_ route: APIRouter) async throws {
        let request = try buildRequest(route)
        let (_, response) = try await session.data(for: request)
        try validate(response)
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

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AppError.serverError }
        switch http.statusCode {
        case 200...299: return
        case 401:       throw AppError.unauthorized
        case 404:       throw AppError.notFound
        case 400, 409, 422: throw AppError.validationFailed
        default:        throw AppError.serverError
        }
    }
}

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ value: any Encodable) { _encode = value.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
