//
//  UserAPIService.swift
//  Unplugged.Services.Networking
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import UnpluggedShared

struct UserAPIService {
    let client: APIClient

    func getMe() async throws -> User {
        try await client.send(.getMe)
    }
}
