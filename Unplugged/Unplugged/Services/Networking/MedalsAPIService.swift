import Foundation
import UnpluggedShared

struct MedalsAPIService {
    let client: APIClient

    func getMyMedals() async throws -> [UserMedalResponse] {
        try await client.send(.getMyMedals)
    }

    func getCatalog() async throws -> [MedalCatalogEntry] {
        try await client.send(.getMedalCatalog)
    }
}
