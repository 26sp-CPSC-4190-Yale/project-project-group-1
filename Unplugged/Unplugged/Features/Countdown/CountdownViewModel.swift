import Foundation
import Observation

@MainActor
@Observable
final class CountdownViewModel {
    var remaining: TimeInterval = 0
    var totalDuration: TimeInterval = 0
    var isExpired: Bool { remaining <= 0 }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return max(0, min(1, 1 - (remaining / totalDuration)))
    }

    private var tickerTask: Task<Void, Never>?

    func start(endsAt: Date) {
        let now = Date()
        self.totalDuration = max(0, endsAt.timeIntervalSince(now))
        tick(endsAt: endsAt)
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                self.tick(endsAt: endsAt)
                if self.isExpired { return }
            }
        }
    }

    func stop() {
        tickerTask?.cancel()
        tickerTask = nil
    }

    private func tick(endsAt: Date) {
        self.remaining = max(0, endsAt.timeIntervalSinceNow)
    }
}
