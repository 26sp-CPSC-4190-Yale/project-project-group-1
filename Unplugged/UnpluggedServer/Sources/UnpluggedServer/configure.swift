//
//  configure.swift
//  UnpluggedServer
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Fluent
import FluentPostgresDriver
import Vapor

public func configure(_ app: Application) async throws {
    app.databases.use(
        .postgres(configuration: .init(
            hostname: Environment.get("DB_HOST") ?? "localhost", //server and DB on same machine?
            port: Int(Environment.get("DB_PORT") ?? "5432") ?? 5432,
            username: Environment.get("DB_USER") ?? "unplugged",
            password: Environment.get("DB_PASSWORD") ?? "unplugged",
            database: Environment.get("DB_NAME") ?? "unplugged",
            //TODO: change to .require after
            tls: .disable
        )),
        as: .psql
    )

    // Register migrations in dependency order
    app.migrations.add(CreateUsers())
    app.migrations.add(CreateSessions())
    app.migrations.add(CreateParticipants())
    app.migrations.add(CreateFriendships())
    app.migrations.add(CreateGroups())
    app.migrations.add(CreateGroupMembers())
    app.migrations.add(CreateJailbreaks())
    // app.migrations.add(CreateSessionLocations()) // location is now in the rooms table

    try await app.autoMigrate()
}
