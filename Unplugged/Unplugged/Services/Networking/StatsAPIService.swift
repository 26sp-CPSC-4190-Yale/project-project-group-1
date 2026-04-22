//
//  StatsAPIService.swift
//  Unplugged.Services.Networking
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import UnpluggedShared

struct StatsAPIService {
    let client: APIClient

    func getMyStats() async throws -> UserStatsResponse {
        try await client.send(.getStats)
    }
}
