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
import Vapor

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
        tls: .disable // change to .require before production
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

    try await app.autoMigrate()

    let jwtSecret = Environment.get("JWT_SECRET") ?? "dev-secret-change-in-production"
    await app.jwt.keys.add(hmac: HMACKey(key: SymmetricKey(data: Data(jwtSecret.utf8))), digestAlgorithm: .sha256)

    try routes(app)
}
