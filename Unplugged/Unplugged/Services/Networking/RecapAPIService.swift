import Foundation
import UnpluggedShared

struct RecapAPIService {
    let client: APIClient

    func getRecap(sessionID: UUID) async throws -> SessionRecapResponse {
        try await client.send(.getRecap(id: sessionID))
    }
}
