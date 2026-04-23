import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class SessionHistoryViewModel {
    var sessions: [SessionHistoryResponse] = []
    var isLoading = false
    var error: String?

    func load(sessions service: SessionAPIService, cache: LocalCacheService) async {
        if sessions.isEmpty, let cached = cache.readHistory() {
            sessions = cached
        }
        isLoading = true
        error = nil
        do {
            let fresh = try await service.listHistory()
            sessions = fresh
            cache.saveHistory(fresh)
        } catch {
            self.error = "Could not load session history"
        }
        isLoading = false
    }
}
