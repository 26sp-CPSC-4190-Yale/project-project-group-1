import Foundation
import UnpluggedShared

struct StatsAPIService {
    let client: APIClient

    func getMyStats() async throws -> UserStatsResponse {
        try await client.send(.getStats)
    }
}
