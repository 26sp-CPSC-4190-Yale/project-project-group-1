//
//  configure.swift
//  UnpluggedServer
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
import FluentPostgresDriver
import Foundation
import JWT
import NIOSSL
import Vapor
import VaporAPNS

public func configure(_ app: Application) async throws {
    let dbHost = Environment.get("DB_HOST") ?? "localhost"
    let dbPort = Int(Environment.get("DB_PORT") ?? "") ?? 5432
    let dbUser = Environment.get("DB_USER") ?? "unplugged"
    let dbPass = Environment.get("DB_PASSWORD") ?? "unplugged"
    let dbName = Environment.get("DB_NAME") ?? "unplugged"
    let dbConfig = SQLPostgresConfiguration(
        hostname: dbHost,
        port: dbPort,
        username: dbUser,
        password: dbPass,
        database: dbName,
        tls: try .require(.init(configuration: .makeClientConfiguration()))
    )
    app.databases.use(.postgres(configuration: dbConfig), as: .psql)

    // Register migrations in dependency order
    app.migrations.add(CreateUsers())
    app.migrations.add(CreateSessions())
    app.migrations.add(CreateParticipants())
    app.migrations.add(CreateFriendships())
    app.migrations.add(CreateGroups())
    app.migrations.add(CreateGroupMembers())
    app.migrations.add(CreateJailbreaks())
    app.migrations.add(CreateMedal())
    app.migrations.add(CreateUserMedalPivot()) // must come after both user + medal migrations
    // app.migrations.add(CreateSessionLocations()) // location is now in the rooms table
    app.migrations.add(AddDeviceTokenToUsers())
    app.migrations.add(AddPointsToUsers())
    app.migrations.add(AddLifecycleFieldsToRooms())
    app.migrations.add(AddLastSeenToUsers())
    app.migrations.add(AddJailbreakReason())
    app.migrations.add(AddDeletedAtToUsers())
    app.migrations.add(CreateUserBlocks())
    app.migrations.add(CreateUserReports())

    try await app.autoMigrate()

    let jwtSecret = try resolveJWTSecret(environment: app.environment)
    await app.jwt.keys.add(hmac: HMACKey(key: SymmetricKey(data: Data(jwtSecret.utf8))), digestAlgorithm: .sha256)

    try app.configureAPNS()
    try routes(app)
}

/// Resolve the JWT signing secret.
///
/// In production we require `JWT_SECRET` to be set and at least 32 characters. Booting with
/// a short or missing secret would mean every token is signed with a key an attacker can trivially
/// guess — an auth bypass. In development we allow a well-known fallback so local dev works
/// without extra config, but the fallback is rejected for any non-development environment.
private func resolveJWTSecret(environment: Environment) throws -> String {
    if let secret = Environment.get("JWT_SECRET") {
        guard secret.count >= 32 else {
            throw Abort(.internalServerError, reason: "JWT_SECRET must be at least 32 characters")
        }
        return secret
    }

    if environment == .development {
        return "dev-secret-change-in-production-dev-only-32+"
    }

    throw Abort(.internalServerError, reason: "JWT_SECRET must be set in \(environment.name)")
}
