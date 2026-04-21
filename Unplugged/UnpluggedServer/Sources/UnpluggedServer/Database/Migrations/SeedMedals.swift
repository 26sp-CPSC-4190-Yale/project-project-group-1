import Fluent

struct SeedMedals: AsyncMigration {
    static let seeds: [(name: String, description: String, icon: String)] = [
        ("First Session", "Completed your first unplugged session.", "🌱"),
        ("5 Sessions", "Completed five unplugged sessions.", "🔥"),
        ("1 Hour Unplugged", "Spent a full hour unplugged.", "⏳"),
        ("10 Hours Unplugged", "Spent ten hours unplugged.", "🏆"),
    ]

    func prepare(on database: Database) async throws {
        for seed in Self.seeds {
            let existing = try await MedalModel.query(on: database)
                .filter(\.$name == seed.name)
                .first()
            if existing == nil {
                try await MedalModel(
                    name: seed.name,
                    description: seed.description,
                    icon: seed.icon
                ).save(on: database)
            }
        }
    }

    func revert(on database: Database) async throws {
        for seed in Self.seeds {
            try await MedalModel.query(on: database)
                .filter(\.$name == seed.name)
                .delete()
        }
    }
}
