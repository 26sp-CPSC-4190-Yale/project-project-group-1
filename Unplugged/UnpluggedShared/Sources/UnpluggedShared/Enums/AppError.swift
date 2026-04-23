//
//  AppError.swift
//  UnpluggedShared.Enums
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

public enum AppError: String, Codable, Sendable, Error {
    case unauthorized
    case notFound
    case validationFailed
    case serverError
    case sessionFull
    case sessionNotActive
    case rateLimited
    case network
    case screenTimePermissionRevoked
}

