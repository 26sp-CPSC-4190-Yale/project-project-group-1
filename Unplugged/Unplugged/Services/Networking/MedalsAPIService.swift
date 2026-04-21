//
//  MedalsAPIService.swift
//  Unplugged.Services.Networking
//

import Foundation
import UnpluggedShared

struct MedalsAPIService {
    let client: APIClient

    func getMyMedals() async throws -> [UserMedalResponse] {
        try await client.send(.getMyMedals)
    }
}
