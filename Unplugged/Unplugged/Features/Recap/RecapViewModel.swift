import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
final class RecapViewModel {
    var recap: SessionRecapResponse?
    var isLoading = false
    var error: String?

    func load(sessionID: UUID, service: RecapAPIService) async {
        isLoading = true
        error = nil
        do {
            recap = try await service.getRecap(sessionID: sessionID)
        } catch {
            self.error = "Couldn't load recap."
        }
        isLoading = false
    }
}
