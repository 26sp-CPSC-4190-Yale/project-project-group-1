//
//  DependencyContainer.swift
//  Unplugged.App
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Observation

@MainActor
@Observable
class DependencyContainer {
    let cache: LocalCacheService
    let auth: AuthAPIService
    let user: UserAPIService
    let sessions: SessionAPIService
    let friends: FriendAPIService
    let stats: StatsAPIService
    let groups: GroupAPIService
    let recap: RecapAPIService
    let touchTips: TouchTipsService
    let screenTime: ScreenTimeService
    let webSocket: WebSocketClient
    let sessionOrchestrator: SessionOrchestrator

    init() {
        let cache = LocalCacheService()
        let client = APIClient(cache: cache)
        let screenTime = ScreenTimeService()
        let webSocket = WebSocketClient()

        self.cache = cache
        self.auth = AuthAPIService(client: client)
        self.user = UserAPIService(client: client)
        let sessions = SessionAPIService(client: client)
        self.sessions = sessions
        self.friends = FriendAPIService(client: client)
        self.stats = StatsAPIService(client: client)
        self.groups = GroupAPIService(client: client)
        let recap = RecapAPIService(client: client)
        self.recap = recap
        self.touchTips = TouchTipsService()
        self.screenTime = screenTime
        self.webSocket = webSocket
        self.sessionOrchestrator = SessionOrchestrator(
            sessions: sessions,
            recap: recap,
            screenTime: screenTime,
            cache: cache,
            webSocket: webSocket
        )
    }
}
