//
//  ProximityMonitor.swift
//  Unplugged.Services.Composite
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation

enum LockedSessionProximityPolicy {
    /// About 4 feet. Tune here if the locked-room boundary needs to move.
    static let maxDistanceMeters: Double = 1.2
    static let checkIntervalNanoseconds: UInt64 = 30_000_000_000
    static let gracePeriodSeconds: Int = 10
    static let graceCheckIntervalNanoseconds: UInt64 = 1_000_000_000
    static let staleReadingInterval: TimeInterval = 8
    static let recoveryCooldown: TimeInterval = 5
}

struct LockedProximityReading: Sendable {
    let distanceMeters: Double?
    let observedAt: Date
    let reason: String?

    init(distanceMeters: Double?, observedAt: Date, reason: String? = nil) {
        self.distanceMeters = distanceMeters
        self.observedAt = observedAt
        self.reason = reason
    }

    var hasUsableDistance: Bool {
        distanceMeters != nil
    }
}
