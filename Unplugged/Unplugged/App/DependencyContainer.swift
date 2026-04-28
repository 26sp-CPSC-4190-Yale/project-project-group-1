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
    let medals: MedalsAPIService
    let groups: GroupAPIService
    let recap: RecapAPIService
    let touchTips: TouchTipsService
    let screenTime: ScreenTimeService
    let liveActivity: LiveActivityService
    let webSocket: WebSocketClient
    let sessionOrchestrator: SessionOrchestrator

    init() {
        let cache = LocalCacheService()
        // SecItemCopyMatching can block hundreds of ms on a cold keychain, pre-warm off the main actor
        cache.prewarmToken()
        let client = APIClient(cache: cache)
        let screenTime = ScreenTimeService()
        let liveActivity = LiveActivityService()
        let webSocket = WebSocketClient()
        let touchTips = TouchTipsService()

        self.cache = cache
        self.auth = AuthAPIService(client: client)
        self.user = UserAPIService(client: client)
        let sessions = SessionAPIService(client: client)
        self.sessions = sessions
        self.friends = FriendAPIService(client: client)
        self.stats = StatsAPIService(client: client)
        self.medals = MedalsAPIService(client: client)
        self.groups = GroupAPIService(client: client)
        let recap = RecapAPIService(client: client)
        self.recap = recap
        self.touchTips = touchTips
        self.screenTime = screenTime
        self.liveActivity = liveActivity
        self.webSocket = webSocket
        self.sessionOrchestrator = SessionOrchestrator(
            sessions: sessions,
            recap: recap,
            screenTime: screenTime,
            liveActivity: liveActivity,
            cache: cache,
            webSocket: webSocket,
            touchTips: touchTips
        )
    }
}
