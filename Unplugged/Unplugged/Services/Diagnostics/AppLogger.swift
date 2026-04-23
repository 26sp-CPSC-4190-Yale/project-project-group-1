import Foundation
import os
import os.lock

/// Central logger for the Unplugged app. Every subsystem gets a named category so
/// Console.app and `log stream` can filter by it (e.g.
/// `log stream --predicate 'subsystem == "com.unplugged.app" && category == "ws"'`).
///
/// The focus is on FAILURES. Success-path signposts are intentionally minimal —
/// what you care about when triaging a crash report or a support ticket is
/// "what went wrong and what happened just before it." Every `error` / `warning`
/// call on this logger also drops a breadcrumb, so a single `AppLogger.dumpRecent()`
/// at the top of a crash handler (or when you reproduce a bug) gives you the last
/// N relevant events in chronological order.
///
/// # Kill switch
/// Logging itself is never free — even `Logger.debug` formats its arguments, and
/// breadcrumb capture takes a lock. If you suspect logging is contributing to a
/// hang or battery regression, flip the kill switch:
///
///     AppLogger.disable()           // runtime, persisted
///     AppLogger.enable()
///     AppLogger.isEnabled = false   // or set directly
///
/// When disabled, every call on this API short-circuits BEFORE any string
/// formatting or lock acquisition, so the cost of a disabled `AppLogger.network.error(...)`
/// is roughly a single atomic bool load. The watchdog and memory observer also
/// stop their background timers while disabled — see `FailureDiagnostics.swift`.
///
/// The setting persists in UserDefaults under `AppLogger.enabledDefaultsKey` so a
/// toggle in a debug menu or via `defaults write` survives launches.
enum AppLogger {
    static let subsystem = "com.unplugged.app"
    static let enabledDefaultsKey = "com.unplugged.app.logging.enabled"

    // MARK: - Kill switch

    /// Master enable flag. Reads are a single atomic bool load on every log call
    /// — cheap enough that instrumented hot paths stay viable when disabled.
    /// Writes persist to UserDefaults and broadcast via `enabledDidChange`.
    static var isEnabled: Bool {
        get { EnabledFlag.shared.value }
        set { EnabledFlag.shared.set(newValue) }
    }

    /// Fires on the main queue whenever `isEnabled` changes. `FailureDiagnostics`
    /// subscribes to this so the main-thread watchdog and memory monitor stop
    /// their timers when logging is turned off.
    static let enabledDidChange = Notification.Name("com.unplugged.app.logging.enabledDidChange")

    /// Shorthand. Use from debug UI or a hidden gesture.
    static func enable()  { isEnabled = true }
    static func disable() { isEnabled = false }

    /// Call once at launch (before any log call) to apply a persisted setting.
    /// Safe to call multiple times — idempotent.
    static func loadPersistedEnabledFlag(defaults: UserDefaults = .standard) {
        EnabledFlag.shared.loadFromDefaults(defaults)
    }

    // MARK: - Categories
    //
    // One Logger per subsystem so categories show up distinctly in Console.app.
    // Add new ones here as new subsystems land — don't reuse `misc` because it
    // makes filtering useless.

    static let app        = CategoryLogger(category: "app")
    static let launch     = CategoryLogger(category: "launch")
    static let hang       = CategoryLogger(category: "hang")
    static let memory     = CategoryLogger(category: "memory")
    static let network    = CategoryLogger(category: "network")
    static let ws         = CategoryLogger(category: "ws")
    static let auth       = CategoryLogger(category: "auth")
    static let session    = CategoryLogger(category: "session")
    static let shield     = CategoryLogger(category: "shield")
    static let proximity  = CategoryLogger(category: "proximity")
    static let touchTips  = CategoryLogger(category: "touchtips")
    static let screenTime = CategoryLogger(category: "screentime")
    static let cache      = CategoryLogger(category: "cache")
    static let push       = CategoryLogger(category: "push")
    static let onboarding = CategoryLogger(category: "onboarding")
    static let room       = CategoryLogger(category: "room")
    static let profile    = CategoryLogger(category: "profile")
    static let ui         = CategoryLogger(category: "ui")

    // MARK: - Breadcrumbs

    /// Record a free-form breadcrumb. Use this for state transitions you want
    /// visible in the trail leading up to a failure (e.g. "ws_connect",
    /// "shield_engage_begin", "task_cancelled"). Prefer the `error`/`warning`
    /// calls on a CategoryLogger for actual failures — those auto-breadcrumb.
    ///
    /// No-op when the kill switch is off.
    static func breadcrumb(_ category: Breadcrumb.Category,
                           _ name: String,
                           context: [String: Any]? = nil) {
        guard isEnabled else { return }
        BreadcrumbStore.shared.record(
            Breadcrumb(
                time: Date(),
                category: category,
                level: .info,
                name: name,
                context: context.map(Self.formatContext)
            )
        )
    }

    /// Dump the last `limit` breadcrumbs to the log. Call this when you want
    /// to attach context to a failure that isn't itself a logger call — e.g.
    /// from a watchdog tick, an unexpected terminal state, or an ExceptionHandler.
    ///
    /// No-op when the kill switch is off.
    static func dumpRecent(_ category: StaticString = "trail", limit: Int = 50) {
        guard isEnabled else { return }
        let trail = BreadcrumbStore.shared.recent(limit: limit)
        guard !trail.isEmpty else { return }
        let logger = Logger(subsystem: subsystem, category: String(describing: category))
        logger.error("breadcrumb trail (last \(trail.count, privacy: .public)):\n\(trail, privacy: .public)")
    }

    // MARK: - Helpers

    fileprivate static func formatContext(_ context: [String: Any]) -> String {
        context
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(Self.stringify($0.value))" }
            .joined(separator: " ")
    }

    fileprivate static func stringify(_ value: Any) -> String {
        switch value {
        case let s as String: return s
        case let e as Error:  return String(describing: e)
        default:              return String(describing: value)
        }
    }
}

// MARK: - CategoryLogger

/// Wraps `os.Logger` so every warning/error/critical also drops a breadcrumb.
/// Debug/info calls go to `os.Logger` only — they're not part of the failure
/// trail by design (too noisy; the whole point of breadcrumbs is signal).
///
/// Every method short-circuits on `AppLogger.isEnabled == false` BEFORE
/// any string formatting, so disabled logging has near-zero runtime cost.
struct CategoryLogger: Sendable {
    let category: String
    private let logger: Logger

    init(category: String) {
        self.category = category
        self.logger = Logger(subsystem: AppLogger.subsystem, category: category)
    }

    func debug(_ message: @autoclosure () -> String,
               context: @autoclosure () -> [String: Any]? = nil) {
        guard AppLogger.isEnabled else { return }
        let msg = message()
        if let contextText = context().map(AppLogger.formatContext) {
            logger.debug("\(msg, privacy: .public) | \(contextText, privacy: .public)")
        } else {
            logger.debug("\(msg, privacy: .public)")
        }
    }

    func info(_ message: @autoclosure () -> String,
              context: @autoclosure () -> [String: Any]? = nil) {
        guard AppLogger.isEnabled else { return }
        let msg = message()
        if let contextText = context().map(AppLogger.formatContext) {
            logger.info("\(msg, privacy: .public) | \(contextText, privacy: .public)")
        } else {
            logger.info("\(msg, privacy: .public)")
        }
    }

    func notice(_ message: @autoclosure () -> String,
                context: @autoclosure () -> [String: Any]? = nil) {
        guard AppLogger.isEnabled else { return }
        let msg = message()
        if let contextText = context().map(AppLogger.formatContext) {
            logger.notice("\(msg, privacy: .public) | \(contextText, privacy: .public)")
        } else {
            logger.notice("\(msg, privacy: .public)")
        }
    }

    /// Something unexpected happened but the app is continuing. Drops a breadcrumb
    /// so the failure trail has context leading into any downstream error.
    func warning(_ message: @autoclosure () -> String,
                 error: Error? = nil,
                 context: @autoclosure () -> [String: Any]? = nil,
                 file: StaticString = #fileID,
                 line: UInt = #line) {
        guard AppLogger.isEnabled else { return }
        let msg = message()
        let errorText = error.map { " error=\(String(describing: $0))" } ?? ""
        let contextText = context().map(AppLogger.formatContext)
        if let contextText {
            logger.warning("\(msg, privacy: .public)\(errorText, privacy: .public) | \(contextText, privacy: .public) @\(file, privacy: .public):\(line, privacy: .public)")
        } else {
            logger.warning("\(msg, privacy: .public)\(errorText, privacy: .public) @\(file, privacy: .public):\(line, privacy: .public)")
        }
        BreadcrumbStore.shared.record(
            Breadcrumb(
                time: Date(),
                category: Breadcrumb.Category(rawValue: category) ?? .custom(category),
                level: .warning,
                name: msg,
                context: [contextText, error.map { "error=\(String(describing: $0))" }]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .nilIfEmpty
            )
        )
    }

    /// Recoverable failure path. Use for silent-catch replacements, unexpected
    /// nils that force an early return, auth expiry, timeouts, and anything
    /// the user cannot act on but that you want to see in Console.
    func error(_ message: @autoclosure () -> String,
               error: Error? = nil,
               context: @autoclosure () -> [String: Any]? = nil,
               file: StaticString = #fileID,
               line: UInt = #line) {
        guard AppLogger.isEnabled else { return }
        let msg = message()
        let errorText = error.map { " error=\(String(describing: $0))" } ?? ""
        let contextText = context().map(AppLogger.formatContext)
        if let contextText {
            logger.error("\(msg, privacy: .public)\(errorText, privacy: .public) | \(contextText, privacy: .public) @\(file, privacy: .public):\(line, privacy: .public)")
        } else {
            logger.error("\(msg, privacy: .public)\(errorText, privacy: .public) @\(file, privacy: .public):\(line, privacy: .public)")
        }
        BreadcrumbStore.shared.record(
            Breadcrumb(
                time: Date(),
                category: Breadcrumb.Category(rawValue: category) ?? .custom(category),
                level: .error,
                name: msg,
                context: [contextText, error.map { "error=\(String(describing: $0))" }]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .nilIfEmpty
            )
        )
    }

    /// Unrecoverable from the feature's perspective — e.g. keychain corruption,
    /// shield failed and the session can't proceed. Same shape as `.error` but
    /// at `.fault` level so it lights up in log search.
    func critical(_ message: @autoclosure () -> String,
                  error: Error? = nil,
                  context: @autoclosure () -> [String: Any]? = nil,
                  file: StaticString = #fileID,
                  line: UInt = #line) {
        guard AppLogger.isEnabled else { return }
        let msg = message()
        let errorText = error.map { " error=\(String(describing: $0))" } ?? ""
        let contextText = context().map(AppLogger.formatContext)
        if let contextText {
            logger.fault("\(msg, privacy: .public)\(errorText, privacy: .public) | \(contextText, privacy: .public) @\(file, privacy: .public):\(line, privacy: .public)")
        } else {
            logger.fault("\(msg, privacy: .public)\(errorText, privacy: .public) @\(file, privacy: .public):\(line, privacy: .public)")
        }
        BreadcrumbStore.shared.record(
            Breadcrumb(
                time: Date(),
                category: Breadcrumb.Category(rawValue: category) ?? .custom(category),
                level: .critical,
                name: msg,
                context: [contextText, error.map { "error=\(String(describing: $0))" }]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .nilIfEmpty
            )
        )
    }
}

// MARK: - Enabled flag storage

/// Atomic bool + UserDefaults persistence + change notification. Hot-path
/// reads (`value`) are a single `os_unfair_lock` lock cycle; writes are rare
/// (toggled from debug UI), so this simple scheme is plenty fast and avoids
/// needing a lock-free atomic type.
private final class EnabledFlag: @unchecked Sendable {
    static let shared = EnabledFlag()

    private var lock = os_unfair_lock_s()
    private var _value: Bool = true

    var value: Bool {
        os_unfair_lock_lock(&lock)
        let v = _value
        os_unfair_lock_unlock(&lock)
        return v
    }

    func set(_ newValue: Bool) {
        os_unfair_lock_lock(&lock)
        let changed = _value != newValue
        _value = newValue
        os_unfair_lock_unlock(&lock)
        guard changed else { return }
        UserDefaults.standard.set(newValue, forKey: AppLogger.enabledDefaultsKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: AppLogger.enabledDidChange, object: nil)
        }
    }

    func loadFromDefaults(_ defaults: UserDefaults) {
        // Only override if the key is actually present — otherwise keep the
        // default (true) so first-launch installs get logging on.
        guard defaults.object(forKey: AppLogger.enabledDefaultsKey) != nil else { return }
        let persisted = defaults.bool(forKey: AppLogger.enabledDefaultsKey)
        os_unfair_lock_lock(&lock)
        _value = persisted
        os_unfair_lock_unlock(&lock)
    }
}

// MARK: - Breadcrumbs

struct Breadcrumb: Sendable {
    enum Level: String, Sendable { case info, warning, error, critical }
    enum Category: Sendable, Equatable {
        case app, launch, hang, memory, network, ws, auth, session, shield
        case proximity, touchTips, screenTime, cache, push, onboarding, room, profile, ui
        case custom(String)

        init?(rawValue: String) {
            switch rawValue {
            case "app":        self = .app
            case "launch":     self = .launch
            case "hang":       self = .hang
            case "memory":     self = .memory
            case "network":    self = .network
            case "ws":         self = .ws
            case "auth":       self = .auth
            case "session":    self = .session
            case "shield":     self = .shield
            case "proximity":  self = .proximity
            case "touchtips":  self = .touchTips
            case "screentime": self = .screenTime
            case "cache":      self = .cache
            case "push":       self = .push
            case "onboarding": self = .onboarding
            case "room":       self = .room
            case "profile":    self = .profile
            case "ui":         self = .ui
            default:           return nil
            }
        }

        var rawValue: String {
            switch self {
            case .app:        return "app"
            case .launch:     return "launch"
            case .hang:       return "hang"
            case .memory:     return "memory"
            case .network:    return "network"
            case .ws:         return "ws"
            case .auth:       return "auth"
            case .session:    return "session"
            case .shield:     return "shield"
            case .proximity:  return "proximity"
            case .touchTips:  return "touchtips"
            case .screenTime: return "screentime"
            case .cache:      return "cache"
            case .push:       return "push"
            case .onboarding: return "onboarding"
            case .room:       return "room"
            case .profile:    return "profile"
            case .ui:         return "ui"
            case .custom(let s): return s
            }
        }
    }

    let time: Date
    let category: Category
    let level: Level
    let name: String
    let context: String?
}

/// Rolling buffer of the most recent breadcrumbs. The MainThreadWatchdog
/// (and any future crash handler) dumps this when something goes wrong so
/// we know what the app was doing in the moments leading up to the failure.
final class BreadcrumbStore: @unchecked Sendable {
    static let shared = BreadcrumbStore()

    private let lock = NSLock()
    private var storage: [Breadcrumb] = []
    private let maxCount = 120

    private init() {}

    func record(_ crumb: Breadcrumb) {
        lock.lock()
        storage.append(crumb)
        if storage.count > maxCount {
            storage.removeFirst(storage.count - maxCount)
        }
        lock.unlock()
    }

    func recent(limit: Int) -> String {
        lock.lock()
        let slice = Array(storage.suffix(limit))
        lock.unlock()

        guard !slice.isEmpty else { return "" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return slice
            .map { crumb in
                let contextText = crumb.context.map { " | \($0)" } ?? ""
                return "[\(formatter.string(from: crumb.time))] \(crumb.level.rawValue.uppercased()) \(crumb.category.rawValue) \(crumb.name)\(contextText)"
            }
            .joined(separator: "\n")
    }

    /// Clear the buffer — used by tests and by sign-out if we want a clean
    /// trail for the next authenticated user.
    func reset() {
        lock.lock()
        storage.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
