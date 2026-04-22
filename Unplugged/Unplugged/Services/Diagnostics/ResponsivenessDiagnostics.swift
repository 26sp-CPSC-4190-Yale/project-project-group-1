import Foundation
import os

enum ResponsivenessDiagnostics {
    static let subsystem = "com.unplugged.app"

    private static let signpostLog = OSLog(
        subsystem: subsystem,
        category: .pointsOfInterest
    )

    static func begin(_ name: StaticString) -> SignpostInterval {
        let id = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: name, signpostID: id)
        return SignpostInterval(name: name, id: id)
    }

    static func event(_ name: StaticString) {
        os_signpost(.event, log: signpostLog, name: name)
    }

    struct SignpostInterval {
        private let name: StaticString
        private let id: OSSignpostID

        fileprivate init(name: StaticString, id: OSSignpostID) {
            self.name = name
            self.id = id
        }

        func end() {
            os_signpost(.end, log: ResponsivenessDiagnostics.signpostLog, name: name, signpostID: id)
        }
    }
}

#if DEBUG
final class MainThreadWatchdog {
    static let shared = MainThreadWatchdog()

    private let logger = Logger(
        subsystem: ResponsivenessDiagnostics.subsystem,
        category: "main-thread-watchdog"
    )
    private let queue = DispatchQueue(label: "com.unplugged.main-thread-watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var pendingPingStartedAt: DispatchTime?
    private var didLogCurrentStall = false
    private var isRunning = false

    private init() {}

    func start(threshold: TimeInterval = 0.25) {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }

            let thresholdNanos = UInt64(threshold * 1_000_000_000)
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + threshold, repeating: threshold)
            timer.setEventHandler { [weak self] in
                self?.tick(thresholdNanos: thresholdNanos)
            }
            self.timer = timer
            self.isRunning = true
            timer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.pendingPingStartedAt = nil
            self.didLogCurrentStall = false
            self.isRunning = false
        }
    }

    private func tick(thresholdNanos: UInt64) {
        let now = DispatchTime.now()

        if let pendingPingStartedAt {
            let elapsed = now.uptimeNanoseconds - pendingPingStartedAt.uptimeNanoseconds
            if elapsed >= thresholdNanos, !didLogCurrentStall {
                let elapsedMs = Double(elapsed) / 1_000_000
                logger.warning("Main thread stalled for \(elapsedMs, privacy: .public) ms")
                didLogCurrentStall = true
            }
        }

        pendingPingStartedAt = now
        DispatchQueue.main.async { [weak self] in
            self?.queue.async { [weak self] in
                self?.pendingPingStartedAt = nil
                self?.didLogCurrentStall = false
            }
        }
    }
}
#endif
