//
//  BlockService.swift
//  UnpluggedServer.Services
//

import Fluent
import Foundation
import Vapor

/// Helpers for applying user-block filtering across the API.
///
/// Blocks are bidirectional: if A blocks B, neither should see the other in search results,
/// friend lists, or incoming requests. We union both directions into a single set of IDs to
/// strip from any listing endpoint before it returns.
enum BlockService {
    /// User IDs that `viewerID` should not see — either because they blocked that user, or
    /// because that user blocked them.
    static func hiddenUserIDs(for viewerID: UUID, on db: Database) async throws -> Set<UUID> {
        let outgoing = try await UserBlockModel.query(on: db)
            .filter(\.$blockerID == viewerID)
            .all()
        let incoming = try await UserBlockModel.query(on: db)
            .filter(\.$blockedID == viewerID)
            .all()
        var set = Set<UUID>()
        for b in outgoing { set.insert(b.blockedID) }
        for b in incoming { set.insert(b.blockerID) }
        return set
    }

    /// Returns true if either side has blocked the other.
    static func isBlocked(between a: UUID, and b: UUID, on db: Database) async throws -> Bool {
        let count = try await UserBlockModel.query(on: db)
            .group(.or) { group in
                group.group(.and) { g in
                    g.filter(\.$blockerID == a)
                    g.filter(\.$blockedID == b)
                }
                group.group(.and) { g in
                    g.filter(\.$blockerID == b)
                    g.filter(\.$blockedID == a)
                }
            }
            .count()
        return count > 0
    }
}
