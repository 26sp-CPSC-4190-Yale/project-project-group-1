// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UnpluggedServer",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.11.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.9.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "5.1.0"),
        .package(url: "https://github.com/vapor/apns.git", from: "4.0.0"),
        // APNSwift provides APNSCore types not re-exported by vapor/apns
        .package(url: "https://github.com/swift-server-community/APNSwift.git", from: "5.1.0"),
        .package(path: "../UnpluggedShared"),
    ],
    targets: [
        .executableTarget(
            name: "UnpluggedServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "UnpluggedShared", package: "UnpluggedShared"),
                .product(name: "VaporAPNS", package: "apns"),
                .product(name: "APNS", package: "APNSwift"),
            ]
        ),
        .testTarget(
            name: "UnpluggedServerTests",
            dependencies: [
                .target(name: "UnpluggedServer"),
                .product(name: "XCTVapor", package: "vapor"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
            ]
        )
    ]
)
