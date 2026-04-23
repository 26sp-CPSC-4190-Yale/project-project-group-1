import Fluent

struct SeedMoreMedals: AsyncMigration {
    static let seeds: [(name: String, description: String, icon: String)] = [
        ("25 Sessions", "Completed twenty-five unplugged sessions.", "⭐"),
        ("50 Sessions", "Completed fifty unplugged sessions.", "🌟"),
        ("100 Sessions", "Completed one hundred unplugged sessions.", "💯"),

        ("5 Hours Unplugged", "Spent five hours unplugged.", "⏰"),
        ("50 Hours Unplugged", "Spent fifty hours unplugged.", "🎖️"),
        ("100 Hours Unplugged", "Spent one hundred hours unplugged.", "🏅"),

        ("3-Day Streak", "Sessioned three days in a row.", "📅"),
        ("7-Day Streak", "Sessioned seven days in a row.", "⚡"),
        ("30-Day Streak", "Sessioned thirty days in a row.", "🌋"),

        ("First Friend", "Added your first friend.", "🤝"),
        ("Social Circle", "Reached five friends.", "👥"),
        ("Popular", "Reached ten friends.", "🧑‍🤝‍🧑"),

        ("Better Together", "Finished a session with a friend.", "💞"),
        ("Squad Up", "Finished a session with three or more friends.", "👨‍👩‍👧"),

        ("Slip-Up", "Left a session early.", "😅"),
        ("Weak Willed", "Left early five times.", "😬"),
        ("Hall of Shame", "Left early ten times.", "💀"),
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
