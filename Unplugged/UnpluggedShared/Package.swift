//
//  Package.swift
//  UnpluggedShared
//
//  Created by Sebastian Gonzalez on 3/12/26.
//
// File used to Define UnpluggedShared as Package
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UnpluggedShared",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "UnpluggedShared",
            targets: ["UnpluggedShared"]
        )
    ],
    targets: [
        .target(
            name: "UnpluggedShared"
        ),
        .testTarget(
            name: "UnpluggedSharedTests",
            dependencies: ["UnpluggedShared"]
        )
    ]
)
