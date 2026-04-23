import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum FailureDiagnostics {
    private static var didWireEnabledObserver = false

    static func start() {
        wireEnabledObserver()
        applyCurrentEnabledState()
        AppLogger.launch.info("FailureDiagnostics.start (logging=\(AppLogger.isEnabled))")
    }

    static func stop() {
        MainThreadWatchdog.shared.stop()
        MemoryDiagnostics.shared.stop()
    }

    private static func applyCurrentEnabledState() {
        if AppLogger.isEnabled {
            MainThreadWatchdog.shared.start()
            MemoryDiagnostics.shared.start()
        } else {
            MainThreadWatchdog.shared.stop()
            MemoryDiagnostics.shared.stop()
        }
    }

    private static func wireEnabledObserver() {
        guard !didWireEnabledObserver else { return }
        didWireEnabledObserver = true
        NotificationCenter.default.addObserver(
            forName: AppLogger.enabledDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in applyCurrentEnabledState() }
        }
    }
}

// MARK: - MainThreadWatchdog

final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog()

    private let queue = DispatchQueue(label: "com.unplugged.main-thread-watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var pendingPingStartedAt: DispatchTime?
    private var didLogCurrentStall = false
    private var isRunning = false
    private var threshold: TimeInterval = 0.35

    private init() {}

    // 350 ms catches keyboard/picker first-use stalls without false-alarming on normal presentations
    func start(threshold: TimeInterval = 0.35) {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }

            self.threshold = threshold
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
        guard AppLogger.isEnabled else { return }

        let now = DispatchTime.now()

        if let pendingPingStartedAt {
            let elapsed = now.uptimeNanoseconds - pendingPingStartedAt.uptimeNanoseconds
            if elapsed >= thresholdNanos, !didLogCurrentStall {
                let elapsedMs = Double(elapsed) / 1_000_000
                AppLogger.hang.warning(
                    "main thread stalled for \(String(format: "%.0f", elapsedMs)) ms",
                    context: ["threshold_ms": Int(threshold * 1000)]
                )
                AppLogger.dumpRecent("hang", limit: 30)
                didLogCurrentStall = true
            }
            return
        }

        let pingStartedAt = now
        pendingPingStartedAt = pingStartedAt
        DispatchQueue.main.async { [weak self] in
            let completedAt = DispatchTime.now()
            self?.queue.async { [weak self] in
                guard let self,
                      self.pendingPingStartedAt?.uptimeNanoseconds == pingStartedAt.uptimeNanoseconds else { return }
                if self.didLogCurrentStall {
                    let elapsedMs = Double(completedAt.uptimeNanoseconds - pingStartedAt.uptimeNanoseconds) / 1_000_000
                    AppLogger.hang.warning("main thread recovered after \(String(format: "%.0f", elapsedMs)) ms")
                }
                self.pendingPingStartedAt = nil
                self.didLogCurrentStall = false
            }
        }
    }
}

// MARK: - MemoryDiagnostics

final class MemoryDiagnostics: @unchecked Sendable {
    static let shared = MemoryDiagnostics()

    private let queue = DispatchQueue(label: "com.unplugged.memory-diagnostics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var warningObserver: NSObjectProtocol?
    private var isRunning = false
    private var lastSampleBytes: UInt64?
    private var samplesSinceLastWarning = 0

    private let ceilingBytes: UInt64 = 250 * 1024 * 1024
    private let growthAlertBytes: UInt64 = 50 * 1024 * 1024
    private let samplingInterval: TimeInterval = 30

    private init() {}

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.samplesSinceLastWarning = 0
            self.lastSampleBytes = nil
            self.installMemoryWarningObserver()
            self.startTimer()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.timer?.cancel()
            self.timer = nil
            self.removeMemoryWarningObserver()
        }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + samplingInterval, repeating: samplingInterval)
        timer.setEventHandler { [weak self] in self?.sample() }
        self.timer = timer
        timer.resume()
    }

    private func installMemoryWarningObserver() {
        #if canImport(UIKit)
        removeMemoryWarningObserver()
        warningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.handleMemoryWarning() }
        }
        #endif
    }

    private func removeMemoryWarningObserver() {
        #if canImport(UIKit)
        if let warningObserver {
            NotificationCenter.default.removeObserver(warningObserver)
        }
        warningObserver = nil
        #endif
    }

    private func handleMemoryWarning() {
        guard AppLogger.isEnabled else { return }
        let footprint = Self.residentFootprintBytes()
        AppLogger.memory.critical(
            "iOS memory warning received",
            context: [
                "footprint_mb": String(format: "%.1f", Double(footprint) / (1024 * 1024)),
                "ceiling_mb": Int(ceilingBytes / (1024 * 1024))
            ]
        )
        AppLogger.dumpRecent("memory", limit: 40)
        samplesSinceLastWarning = 0
        lastSampleBytes = footprint
    }

    private func sample() {
        guard AppLogger.isEnabled else { return }
        let footprint = Self.residentFootprintBytes()
        defer {
            lastSampleBytes = footprint
            samplesSinceLastWarning += 1
        }

        guard footprint > 0 else { return }

        if footprint >= ceilingBytes {
            AppLogger.memory.warning(
                "footprint crossed ceiling",
                context: [
                    "footprint_mb": String(format: "%.1f", Double(footprint) / (1024 * 1024)),
                    "ceiling_mb": Int(ceilingBytes / (1024 * 1024))
                ]
            )
            return
        }

        if let lastSampleBytes,
           footprint > lastSampleBytes,
           footprint - lastSampleBytes >= growthAlertBytes,
           samplesSinceLastWarning >= 1 {
            let deltaMB = Double(footprint - lastSampleBytes) / (1024 * 1024)
            let footprintMB = Double(footprint) / (1024 * 1024)
            AppLogger.memory.warning(
                "footprint grew sharply without a memory warning",
                context: [
                    "delta_mb": String(format: "%.1f", deltaMB),
                    "footprint_mb": String(format: "%.1f", footprintMB),
                    "interval_s": Int(samplingInterval)
                ]
            )
        }
    }

    // phys_footprint, not resident_size, is what iOS measures against the kill threshold
    static func residentFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
