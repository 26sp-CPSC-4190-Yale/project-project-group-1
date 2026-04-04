//
//  DependencyContainer.swift
//  Unplugged.App
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Observation

@Observable
class DependencyContainer {
    let cache: LocalCacheService
    let auth: AuthAPIService
    let user: UserAPIService
    let sessions: SessionAPIService
    let friends: FriendAPIService

    init() {
        let cache = LocalCacheService()
        let client = APIClient(cache: cache)
        self.cache = cache
        self.auth = AuthAPIService(client: client)
        self.user = UserAPIService(client: client)
        self.sessions = SessionAPIService(client: client)
        self.friends = FriendAPIService(client: client)
    }
}
