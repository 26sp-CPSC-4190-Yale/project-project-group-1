import Foundation

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
    }

    private struct FinishedSpan {
        let name: String
        let durationMs: Double
        let file: String
        let line: UInt
        let finishedAt: DispatchTime
    }

    struct Snapshot: Sendable {
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
    private let maxRecentSpans = 20

    private init() {}

    func begin(
        name: String,
        category: Breadcrumb.Category,
        context: [String: Any]?,
        warnAfter: TimeInterval,
        file: StaticString,
        line: UInt
    ) -> MainThreadTraceToken {
        let id: UInt64
        let span = ActiveSpan(
            id: 0,
            name: name,
            category: category,
            context: context.map(AppLogger.formatContext),
            warnAfter: warnAfter,
            file: String(describing: file),
            line: line,
            startedAt: .now()
        )

        lock.lock()
        id = nextID
        nextID += 1
        activeSpans[id] = ActiveSpan(
            id: id,
            name: span.name,
            category: span.category,
            context: span.context,
            warnAfter: span.warnAfter,
            file: span.file,
            line: span.line,
            startedAt: span.startedAt
        )
        lock.unlock()

        return MainThreadTraceToken(tracker: self, id: id)
    }

    func end(id: UInt64) {
        let finishedAt = DispatchTime.now()

        lock.lock()
        guard let span = activeSpans.removeValue(forKey: id) else {
            lock.unlock()
            return
        }

        let durationMs = Self.milliseconds(from: span.startedAt, to: finishedAt)
        recentSpans.append(
            FinishedSpan(
                name: span.name,
                durationMs: durationMs,
                file: span.file,
                line: span.line,
                finishedAt: finishedAt
            )
        )
        if recentSpans.count > maxRecentSpans {
            recentSpans.removeFirst(recentSpans.count - maxRecentSpans)
        }
        lock.unlock()

        guard durationMs >= span.warnAfter * 1_000 else { return }

        var logContext: [String: Any] = [
            "duration_ms": Self.round(durationMs),
            "threshold_ms": Int(span.warnAfter * 1_000),
            "file": span.file,
            "line": span.line
        ]
        if let context = span.context {
            logContext["span_context"] = context
        }

        AppLogger.hang.warning(
            "slow main-thread work: \(span.name)",
            context: logContext
        )
    }

    func snapshot(activeLimit: Int = 8, recentLimit: Int = 8) -> Snapshot {
        let now = DispatchTime.now()

        lock.lock()
        let active = activeSpans.values
            .sorted { $0.startedAt.uptimeNanoseconds < $1.startedAt.uptimeNanoseconds }
        let recent = recentSpans
            .sorted { $0.finishedAt.uptimeNanoseconds > $1.finishedAt.uptimeNanoseconds }
        lock.unlock()

        let activeLines = active.prefix(activeLimit).map { span in
            let elapsedMs = Self.milliseconds(from: span.startedAt, to: now)
            let context = span.context.map { " | \($0)" } ?? ""
            return "#\(span.id) \(span.name) active \(Self.round(elapsedMs))ms @\(span.file):\(span.line)\(context)"
        }

        let recentLines = recent.prefix(recentLimit).map { span in
            "\(span.name) \(Self.round(span.durationMs))ms @\(span.file):\(span.line)"
        }

        let oldestActiveMs = active.first.map { Self.milliseconds(from: $0.startedAt, to: now) }

        return Snapshot(
            activeCount: active.count,
            oldestActiveMs: oldestActiveMs,
            activeLines: activeLines,
            recentLines: recentLines
        )
    }

    func logSnapshot(reason: String, snapshot: Snapshot? = nil) {
        guard AppLogger.isEnabled else { return }
        let snapshot = snapshot ?? self.snapshot()

        if snapshot.activeLines.isEmpty {
            AppLogger.hang.notice("no traced main-thread work active during \(reason)")
        } else {
            AppLogger.hang.notice(
                "traced main-thread work active during \(reason):\n\(snapshot.activeLines.joined(separator: "\n"))"
            )
        }

        if !snapshot.recentLines.isEmpty {
            AppLogger.hang.notice(
                "recent traced main-thread work before \(reason):\n\(snapshot.recentLines.joined(separator: "\n"))"
            )
        }
    }

    private static func milliseconds(from start: DispatchTime, to end: DispatchTime) -> Double {
        Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    private static func round(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

final class MainRunLoopActivityTracker: @unchecked Sendable {
    static let shared = MainRunLoopActivityTracker()

    struct Snapshot: Sendable {
        let activity: String
        let ageMs: Double
    }

    private let lock = NSLock()
    private var observer: CFRunLoopObserver?
    private var lastActivity = "not_installed"
    private var lastActivityAt = DispatchTime.now()

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
    }

    func stop() {
        guard Thread.isMainThread else { return }
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
        observer = nil

        lock.lock()
        lastActivity = "not_installed"
        lastActivityAt = .now()
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        let now = DispatchTime.now()

        lock.lock()
        let activity = lastActivity
        let activityAt = lastActivityAt
        lock.unlock()

        return Snapshot(
            activity: activity,
            ageMs: Double(now.uptimeNanoseconds - activityAt.uptimeNanoseconds) / 1_000_000
        )
    }

    private func record(_ activity: CFRunLoopActivity) {
        lock.lock()
        lastActivity = Self.name(for: activity)
        lastActivityAt = .now()
        lock.unlock()
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
