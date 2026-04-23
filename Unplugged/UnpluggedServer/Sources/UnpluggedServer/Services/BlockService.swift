import Fluent
import Foundation
import Vapor

enum BlockService {
    // bidirectional, returns both outgoing and incoming blocks as one union so list endpoints strip both sides
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
