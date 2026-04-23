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
    /// NearbyInteraction does not guarantee a new distance sample every second,
    /// especially while the devices are stationary or the radio is reacquiring.
    /// Keep this comfortably longer than the leave countdown so a single valid
    /// out-of-range reading can carry the full warning window.
    static let staleReadingInterval: TimeInterval = TimeInterval(gracePeriodSeconds + 8)
    /// A stale-but-real distance sample is still better than tearing the entire
    /// MC/NI stack down immediately. Give the transport a wider window before
    /// forcing a full recovery.
    static let staleRecoveryInterval: TimeInterval = 45
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
