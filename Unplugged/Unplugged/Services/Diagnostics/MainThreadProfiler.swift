import Foundation

private enum MainThreadDiagnosticsConfig {
    static let logEveryTracedSpan = true
    static let recordLifecycleBreadcrumbs = true
    static let captureStackSymbols = true
    static let maxCapturedStackFrames = 32
    static let maxSnapshotStackFrames = 12
    static let runLoopGapWarnAfterMs = 100.0
}

private enum MainThreadDiagnosticsFormat {
    static func milliseconds(from start: DispatchTime, to end: DispatchTime) -> Double {
        Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    static func ms(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func captureStackSymbols() -> [String] {
        guard MainThreadDiagnosticsConfig.captureStackSymbols else { return [] }
        return Array(Thread.callStackSymbols.dropFirst(2).prefix(MainThreadDiagnosticsConfig.maxCapturedStackFrames))
    }

    static func formatStack(_ stack: [String], limit: Int, indent: String = "  ") -> String {
        stack.prefix(limit).enumerated()
            .map { index, frame in "\(indent)[\(index)] \(frame)" }
            .joined(separator: "\n")
    }

    static func footprintMB() -> String? {
        let bytes = MemoryDiagnostics.residentFootprintBytes()
        guard bytes > 0 else { return nil }
        return String(format: "%.1f", Double(bytes) / (1024 * 1024))
    }
}

extension AppLogger {
    @discardableResult
    static func beginMainThreadWork(
        _ name: @autoclosure () -> String,
        category: Breadcrumb.Category = .ui,
        context: @autoclosure () -> [String: Any]? = nil,
        warnAfter: TimeInterval = 0.05,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> MainThreadTraceToken {
        guard isEnabled, Thread.isMainThread else {
            return MainThreadTraceToken.inactive()
        }

        return MainThreadActivityTracker.shared.begin(
            name: name(),
            category: category,
            context: context(),
            warnAfter: warnAfter,
            file: file,
            line: line
        )
    }

    static func measureMainThreadWork<T>(
        _ name: @autoclosure () -> String,
        category: Breadcrumb.Category = .ui,
        context: @autoclosure () -> [String: Any]? = nil,
        warnAfter: TimeInterval = 0.05,
        file: StaticString = #fileID,
        line: UInt = #line,
        _ work: () throws -> T
    ) rethrows -> T {
        let token = beginMainThreadWork(
            name(),
            category: category,
            context: context(),
            warnAfter: warnAfter,
            file: file,
            line: line
        )
        defer { token.end() }
        return try work()
    }
}

final class MainThreadTraceToken: @unchecked Sendable {
    private let tracker: MainThreadActivityTracker?
    private let id: UInt64?
    private let lock = NSLock()
    private var didEnd = false

    static func inactive() -> MainThreadTraceToken {
        MainThreadTraceToken(tracker: nil, id: nil)
    }

    init(tracker: MainThreadActivityTracker?, id: UInt64?) {
        self.tracker = tracker
        self.id = id
    }

    func end() {
        lock.lock()
        guard !didEnd else {
            lock.unlock()
            return
        }
        didEnd = true
        lock.unlock()

        guard let tracker, let id else { return }
        tracker.end(id: id)
    }

    deinit {
        end()
    }
}

final class MainThreadActivityTracker: @unchecked Sendable {
    static let shared = MainThreadActivityTracker()

    private struct ActiveSpan {
        let id: UInt64
        let name: String
        let category: Breadcrumb.Category
        let context: String?
        let warnAfter: TimeInterval
        let file: String
        let line: UInt
        let startedAt: DispatchTime
        let startedAtWallClock: Date
        let threadName: String
        let threadQoS: String
        let operationQueueName: String
        let startRunLoopActivity: String
        let startRunLoopMode: String
        let startRunLoopActivityAgeMs: Double
        let stackSymbols: [String]
    }

    private struct FinishedSpan {
        let id: UInt64
        let name: String
        let category: Breadcrumb.Category
        let context: String?
        let warnAfter: TimeInterval
        let durationMs: Double
        let file: String
        let line: UInt
        let startedAtWallClock: Date
        let finishedAt: DispatchTime
        let startRunLoopActivity: String
        let startRunLoopMode: String
        let threadName: String
        let threadQoS: String
        let operationQueueName: String
        let stackTop: String?
    }

    struct Snapshot: Sendable {
        let capturedAt: Date
        let activeCount: Int
        let oldestActiveMs: Double?
        let activeLines: [String]
        let recentLines: [String]

        var hasDetails: Bool {
            !activeLines.isEmpty || !recentLines.isEmpty
        }
    }

    private let lock = NSLock()
    private var nextID: UInt64 = 1
    private var activeSpans: [UInt64: ActiveSpan] = [:]
    private var recentSpans: [FinishedSpan] = []
    private let maxRecentSpans = 60

    private init() {}

    func begin(
        name: String,
        category: Breadcrumb.Category,
        context: [String: Any]?,
        warnAfter: TimeInterval,
        file: StaticString,
        line: UInt
    ) -> MainThreadTraceToken {
        let runLoopSnapshot = MainRunLoopActivityTracker.shared.snapshot(recentLimit: 0)
        let spanContext = context.map(AppLogger.formatContext)
        let stackSymbols = MainThreadDiagnosticsFormat.captureStackSymbols()
        let thread = Thread.current
        let operationQueueName = OperationQueue.current?.name ?? "none"
        let threadName = thread.name?.isEmpty == false ? thread.name! : "unnamed"
        let threadQoS = String(describing: thread.qualityOfService)
        let startedAt = DispatchTime.now()
        let startedAtWallClock = Date()

        let id: UInt64
        let activeDepthBefore: Int
        let activeCountAfter: Int
        let span: ActiveSpan

        lock.lock()
        id = nextID
        nextID += 1
        activeDepthBefore = activeSpans.count
        span = ActiveSpan(
            id: id,
            name: name,
            category: category,
            context: spanContext,
            warnAfter: warnAfter,
            file: String(describing: file),
            line: line,
            startedAt: startedAt,
            startedAtWallClock: startedAtWallClock,
            threadName: threadName,
            threadQoS: threadQoS,
            operationQueueName: operationQueueName,
            startRunLoopActivity: runLoopSnapshot.activity,
            startRunLoopMode: runLoopSnapshot.mode,
            startRunLoopActivityAgeMs: runLoopSnapshot.ageMs,
            stackSymbols: stackSymbols
        )
        activeSpans[id] = span
        activeCountAfter = activeSpans.count
        lock.unlock()

        if MainThreadDiagnosticsConfig.logEveryTracedSpan {
            AppLogger.mainThread.notice(
                "main-thread span begin: \(span.name)",
                context: beginLogContext(
                    span,
                    activeDepthBefore: activeDepthBefore,
                    activeCountAfter: activeCountAfter
                )
            )
        }

        if MainThreadDiagnosticsConfig.recordLifecycleBreadcrumbs {
            AppLogger.breadcrumb(
                category,
                "main_thread_span_begin",
                context: [
                    "id": id,
                    "name": span.name,
                    "active_depth_before": activeDepthBefore,
                    "file": span.file,
                    "line": span.line
                ]
            )
        }

        return MainThreadTraceToken(tracker: self, id: id)
    }

    func end(id: UInt64) {
        let finishedAt = DispatchTime.now()
        let footprintMB = MainThreadDiagnosticsFormat.footprintMB()

        let span: ActiveSpan
        let durationMs: Double
        let remainingActiveCount: Int

        lock.lock()
        guard let activeSpan = activeSpans.removeValue(forKey: id) else {
            lock.unlock()
            return
        }

        span = activeSpan
        durationMs = MainThreadDiagnosticsFormat.milliseconds(from: span.startedAt, to: finishedAt)
        recentSpans.append(
            FinishedSpan(
                id: span.id,
                name: span.name,
                category: span.category,
                context: span.context,
                warnAfter: span.warnAfter,
                durationMs: durationMs,
                file: span.file,
                line: span.line,
                startedAtWallClock: span.startedAtWallClock,
                finishedAt: finishedAt,
                startRunLoopActivity: span.startRunLoopActivity,
                startRunLoopMode: span.startRunLoopMode,
                threadName: span.threadName,
                threadQoS: span.threadQoS,
                operationQueueName: span.operationQueueName,
                stackTop: span.stackSymbols.first
            )
        )
        if recentSpans.count > maxRecentSpans {
            recentSpans.removeFirst(recentSpans.count - maxRecentSpans)
        }
        remainingActiveCount = activeSpans.count
        lock.unlock()

        let exceededThreshold = durationMs >= span.warnAfter * 1_000
        if MainThreadDiagnosticsConfig.logEveryTracedSpan {
            AppLogger.mainThread.notice(
                "main-thread span end: \(span.name)",
                context: endLogContext(
                    span,
                    durationMs: durationMs,
                    exceededThreshold: exceededThreshold,
                    remainingActiveCount: remainingActiveCount,
                    footprintMB: footprintMB
                )
            )
        }

        if MainThreadDiagnosticsConfig.recordLifecycleBreadcrumbs {
            AppLogger.breadcrumb(
                span.category,
                "main_thread_span_end",
                context: [
                    "id": span.id,
                    "name": span.name,
                    "duration_ms": MainThreadDiagnosticsFormat.ms(durationMs),
                    "threshold_ms": Int(span.warnAfter * 1_000),
                    "exceeded_threshold": exceededThreshold,
                    "remaining_active": remainingActiveCount
                ]
            )
        }

        guard exceededThreshold else { return }

        var logContext = endLogContext(
            span,
            durationMs: durationMs,
            exceededThreshold: true,
            remainingActiveCount: remainingActiveCount,
            footprintMB: footprintMB
        )
        logContext["captured_stack_frames"] = span.stackSymbols.count

        AppLogger.hang.warning(
            "slow main-thread work: \(span.name)",
            context: logContext
        )
        AppLogger.mainThread.warning(
            "main-thread span exceeded threshold: \(span.name)",
            context: logContext
        )

        if !span.stackSymbols.isEmpty {
            AppLogger.mainThread.notice(
                "call stack captured at start of slow main-thread span #\(span.id):\n\(MainThreadDiagnosticsFormat.formatStack(span.stackSymbols, limit: MainThreadDiagnosticsConfig.maxCapturedStackFrames))"
            )
        }
    }

    func snapshot(activeLimit: Int = 12, recentLimit: Int = 16) -> Snapshot {
        let now = DispatchTime.now()
        let capturedAt = Date()

        lock.lock()
        let active = activeSpans.values
            .sorted { $0.startedAt.uptimeNanoseconds < $1.startedAt.uptimeNanoseconds }
        let recent = recentSpans
            .sorted { $0.finishedAt.uptimeNanoseconds > $1.finishedAt.uptimeNanoseconds }
        lock.unlock()

        let activeLines = active.prefix(activeLimit).map { span in
            let elapsedMs = MainThreadDiagnosticsFormat.milliseconds(from: span.startedAt, to: now)
            let contextLine = span.context.map { "\n  context: \($0)" } ?? ""
            let stackLine: String
            if span.stackSymbols.isEmpty {
                stackLine = ""
            } else {
                stackLine = "\n  start stack:\n\(MainThreadDiagnosticsFormat.formatStack(span.stackSymbols, limit: MainThreadDiagnosticsConfig.maxSnapshotStackFrames, indent: "    "))"
            }
            return """
            #\(span.id) \(span.name) category=\(span.category.rawValue) active_ms=\(MainThreadDiagnosticsFormat.ms(elapsedMs)) threshold_ms=\(Int(span.warnAfter * 1_000)) started=\(MainThreadDiagnosticsFormat.isoString(span.startedAtWallClock)) @\(span.file):\(span.line)
              start_state: runloop=\(span.startRunLoopActivity) mode=\(span.startRunLoopMode) runloop_age_ms=\(MainThreadDiagnosticsFormat.ms(span.startRunLoopActivityAgeMs)) thread=\(span.threadName) qos=\(span.threadQoS) operation_queue=\(span.operationQueueName)\(contextLine)\(stackLine)
            """
        }

        let recentLines = recent.prefix(recentLimit).map { span in
            let ageMs = MainThreadDiagnosticsFormat.milliseconds(from: span.finishedAt, to: now)
            let thresholdMs = span.warnAfter * 1_000
            let status = span.durationMs >= thresholdMs ? "slow" : "ok"
            let contextLine = span.context.map { " context=\($0)" } ?? ""
            let stackTop = span.stackTop.map { " stack_top=\($0)" } ?? ""
            return "#\(span.id) \(span.name) category=\(span.category.rawValue) status=\(status) duration_ms=\(MainThreadDiagnosticsFormat.ms(span.durationMs)) threshold_ms=\(Int(thresholdMs)) age_ms=\(MainThreadDiagnosticsFormat.ms(ageMs)) started=\(MainThreadDiagnosticsFormat.isoString(span.startedAtWallClock)) @\(span.file):\(span.line) runloop_start=\(span.startRunLoopActivity) mode=\(span.startRunLoopMode) thread=\(span.threadName) qos=\(span.threadQoS) operation_queue=\(span.operationQueueName)\(contextLine)\(stackTop)"
        }

        let oldestActiveMs = active.first.map { MainThreadDiagnosticsFormat.milliseconds(from: $0.startedAt, to: now) }

        return Snapshot(
            capturedAt: capturedAt,
            activeCount: active.count,
            oldestActiveMs: oldestActiveMs,
            activeLines: activeLines,
            recentLines: recentLines
        )
    }

    func logSnapshot(reason: String, snapshot: Snapshot? = nil) {
        guard AppLogger.isEnabled else { return }
        let snapshot = snapshot ?? self.snapshot()

        var summaryContext: [String: Any] = [
            "reason": reason,
            "captured_at": MainThreadDiagnosticsFormat.isoString(snapshot.capturedAt),
            "active_count": snapshot.activeCount
        ]
        if let oldestActiveMs = snapshot.oldestActiveMs {
            summaryContext["oldest_active_ms"] = MainThreadDiagnosticsFormat.ms(oldestActiveMs)
        }
        AppLogger.mainThread.notice("main-thread trace snapshot", context: summaryContext)

        if snapshot.activeLines.isEmpty {
            AppLogger.hang.notice("no traced main-thread work active during \(reason)")
            AppLogger.mainThread.notice("no traced main-thread work active during \(reason)")
        } else {
            let activeDetails = snapshot.activeLines.joined(separator: "\n")
            AppLogger.hang.notice("traced main-thread work active during \(reason):\n\(activeDetails)")
            AppLogger.mainThread.notice("active main-thread spans during \(reason):\n\(activeDetails)")
        }

        if !snapshot.recentLines.isEmpty {
            let recentDetails = snapshot.recentLines.joined(separator: "\n")
            AppLogger.hang.notice("recent traced main-thread work before \(reason):\n\(recentDetails)")
            AppLogger.mainThread.notice("recent main-thread spans before \(reason):\n\(recentDetails)")
        }
    }

    private func beginLogContext(
        _ span: ActiveSpan,
        activeDepthBefore: Int,
        activeCountAfter: Int
    ) -> [String: Any] {
        var context: [String: Any] = [
            "id": span.id,
            "category": span.category.rawValue,
            "file": span.file,
            "line": span.line,
            "threshold_ms": Int(span.warnAfter * 1_000),
            "active_depth_before": activeDepthBefore,
            "active_count_after": activeCountAfter,
            "started_at": MainThreadDiagnosticsFormat.isoString(span.startedAtWallClock),
            "runloop_activity_at_start": span.startRunLoopActivity,
            "runloop_mode_at_start": span.startRunLoopMode,
            "runloop_activity_age_ms_at_start": MainThreadDiagnosticsFormat.ms(span.startRunLoopActivityAgeMs),
            "thread_name": span.threadName,
            "thread_qos": span.threadQoS,
            "operation_queue": span.operationQueueName,
            "captured_stack_frames": span.stackSymbols.count
        ]
        if let spanContext = span.context {
            context["span_context"] = spanContext
        }
        return context
    }

    private func endLogContext(
        _ span: ActiveSpan,
        durationMs: Double,
        exceededThreshold: Bool,
        remainingActiveCount: Int,
        footprintMB: String?
    ) -> [String: Any] {
        var context: [String: Any] = [
            "id": span.id,
            "category": span.category.rawValue,
            "duration_ms": MainThreadDiagnosticsFormat.ms(durationMs),
            "threshold_ms": Int(span.warnAfter * 1_000),
            "exceeded_threshold": exceededThreshold,
            "remaining_active": remainingActiveCount,
            "file": span.file,
            "line": span.line,
            "started_at": MainThreadDiagnosticsFormat.isoString(span.startedAtWallClock),
            "runloop_activity_at_start": span.startRunLoopActivity,
            "runloop_mode_at_start": span.startRunLoopMode,
            "runloop_activity_age_ms_at_start": MainThreadDiagnosticsFormat.ms(span.startRunLoopActivityAgeMs),
            "thread_name": span.threadName,
            "thread_qos": span.threadQoS,
            "operation_queue": span.operationQueueName
        ]
        if let footprintMB {
            context["footprint_mb"] = footprintMB
        }
        if let spanContext = span.context {
            context["span_context"] = spanContext
        }
        return context
    }
}

final class MainRunLoopActivityTracker: @unchecked Sendable {
    static let shared = MainRunLoopActivityTracker()

    struct Snapshot: Sendable {
        let activity: String
        let ageMs: Double
        let mode: String
        let transitionCount: UInt64
        let recentLines: [String]
    }

    private struct Event {
        let sequence: UInt64
        let activity: String
        let mode: String
        let recordedAt: DispatchTime
        let deltaMs: Double?
    }

    private struct LongGap {
        let previousActivity: String
        let previousMode: String
        let currentActivity: String
        let currentMode: String
        let gapMs: Double
        let sequence: UInt64
    }

    private let lock = NSLock()
    private var observer: CFRunLoopObserver?
    private var lastActivity = "not_installed"
    private var lastMode = "unknown"
    private var lastActivityAt = DispatchTime.now()
    private var transitionCount: UInt64 = 0
    private var recentEvents: [Event] = []
    private let maxRecentEvents = 80

    private init() {}

    func start() {
        guard Thread.isMainThread, observer == nil else { return }

        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.allActivities.rawValue,
            true,
            0
        ) { _, activity in
            MainRunLoopActivityTracker.shared.record(activity)
        }

        guard let observer else { return }
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        record(.entry)
        AppLogger.mainThread.notice(
            "main run-loop tracker started",
            context: ["mode": Self.currentModeName()]
        )
    }

    func stop() {
        guard Thread.isMainThread else { return }
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
        observer = nil

        lock.lock()
        lastActivity = "not_installed"
        lastMode = "unknown"
        lastActivityAt = .now()
        transitionCount = 0
        recentEvents.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func snapshot(recentLimit: Int = 12) -> Snapshot {
        let now = DispatchTime.now()

        lock.lock()
        let activity = lastActivity
        let mode = lastMode
        let activityAt = lastActivityAt
        let count = transitionCount
        let events = Array(recentEvents.suffix(recentLimit))
        lock.unlock()

        let recentLines = events.reversed().map { event in
            let ageMs = MainThreadDiagnosticsFormat.milliseconds(from: event.recordedAt, to: now)
            let delta = event.deltaMs.map { MainThreadDiagnosticsFormat.ms($0) } ?? "n/a"
            return "#\(event.sequence) \(event.activity) mode=\(event.mode) age_ms=\(MainThreadDiagnosticsFormat.ms(ageMs)) delta_since_previous_ms=\(delta)"
        }

        return Snapshot(
            activity: activity,
            ageMs: MainThreadDiagnosticsFormat.milliseconds(from: activityAt, to: now),
            mode: mode,
            transitionCount: count,
            recentLines: recentLines
        )
    }

    func logSnapshot(reason: String, snapshot: Snapshot? = nil) {
        guard AppLogger.isEnabled else { return }
        let snapshot = snapshot ?? self.snapshot()

        AppLogger.mainThread.notice(
            "main run-loop snapshot during \(reason)",
            context: [
                "activity": snapshot.activity,
                "activity_age_ms": MainThreadDiagnosticsFormat.ms(snapshot.ageMs),
                "mode": snapshot.mode,
                "transition_count": snapshot.transitionCount
            ]
        )

        if !snapshot.recentLines.isEmpty {
            AppLogger.mainThread.notice(
                "recent main run-loop transitions before \(reason):\n\(snapshot.recentLines.joined(separator: "\n"))"
            )
        }
    }

    private func record(_ activity: CFRunLoopActivity) {
        let now = DispatchTime.now()
        let activityName = Self.name(for: activity)
        let mode = Self.currentModeName()
        let longGap: LongGap?

        lock.lock()
        let previousActivity = lastActivity
        let previousMode = lastMode
        let previousAt = lastActivityAt
        let deltaMs = MainThreadDiagnosticsFormat.milliseconds(from: previousAt, to: now)
        transitionCount += 1
        let sequence = transitionCount

        lastActivity = activityName
        lastMode = mode
        lastActivityAt = now

        recentEvents.append(
            Event(
                sequence: sequence,
                activity: activityName,
                mode: mode,
                recordedAt: now,
                deltaMs: previousActivity == "not_installed" ? nil : deltaMs
            )
        )
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeFirst(recentEvents.count - maxRecentEvents)
        }

        // A long before_waiting -> after_waiting gap is normal idle sleep, not main-thread work.
        if previousActivity != "not_installed",
           previousActivity != "before_waiting",
           deltaMs >= MainThreadDiagnosticsConfig.runLoopGapWarnAfterMs {
            longGap = LongGap(
                previousActivity: previousActivity,
                previousMode: previousMode,
                currentActivity: activityName,
                currentMode: mode,
                gapMs: deltaMs,
                sequence: sequence
            )
        } else {
            longGap = nil
        }
        lock.unlock()

        if let longGap {
            logLongGap(longGap)
        }
    }

    private func logLongGap(_ gap: LongGap) {
        guard AppLogger.isEnabled else { return }
        AppLogger.mainThread.warning(
            "main run-loop gap detected",
            context: [
                "gap_ms": MainThreadDiagnosticsFormat.ms(gap.gapMs),
                "threshold_ms": Int(MainThreadDiagnosticsConfig.runLoopGapWarnAfterMs),
                "previous_activity": gap.previousActivity,
                "previous_mode": gap.previousMode,
                "current_activity": gap.currentActivity,
                "current_mode": gap.currentMode,
                "transition_sequence": gap.sequence
            ]
        )

        let runLoopSnapshot = snapshot()
        logSnapshot(reason: "runloop_gap", snapshot: runLoopSnapshot)
        MainThreadActivityTracker.shared.logSnapshot(reason: "runloop_gap")
        AppLogger.dumpRecent("main_thread", limit: 60)
    }

    private static func currentModeName() -> String {
        guard let mode = CFRunLoopCopyCurrentMode(CFRunLoopGetMain()) else { return "none" }
        return String(describing: mode)
    }

    private static func name(for activity: CFRunLoopActivity) -> String {
        if activity == .entry { return "entry" }
        if activity == .beforeTimers { return "before_timers" }
        if activity == .beforeSources { return "before_sources" }
        if activity == .beforeWaiting { return "before_waiting" }
        if activity == .afterWaiting { return "after_waiting" }
        if activity == .exit { return "exit" }
        return "unknown_\(activity.rawValue)"
    }
}
