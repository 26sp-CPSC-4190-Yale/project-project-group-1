import Foundation
import os
import os.lock

enum AppLogger {
    static let subsystem = "com.unplugged.app"
    static let enabledDefaultsKey = "com.unplugged.app.logging.enabled"

    // MARK: - Kill switch

    static var isEnabled: Bool {
        get { EnabledFlag.shared.value }
        set { EnabledFlag.shared.set(newValue) }
    }

    static let enabledDidChange = Notification.Name("com.unplugged.app.logging.enabledDidChange")

    static func enable()  { isEnabled = true }
    static func disable() { isEnabled = false }

    static func loadPersistedEnabledFlag(defaults: UserDefaults = .standard) {
        EnabledFlag.shared.loadFromDefaults(defaults)
    }

    // MARK: - Categories

    static let app        = CategoryLogger(category: "app")
    static let launch     = CategoryLogger(category: "launch")
    static let hang       = CategoryLogger(category: "hang")
    static let memory     = CategoryLogger(category: "memory")
    static let mainThread = CategoryLogger(category: "main_thread")
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

    static func dumpRecent(_ category: StaticString = "trail", limit: Int = 50) {
        guard isEnabled else { return }
        let trail = BreadcrumbStore.shared.recent(limit: limit)
        guard !trail.isEmpty else { return }
        let logger = Logger(subsystem: subsystem, category: String(describing: category))
        logger.error("breadcrumb trail (last \(trail.count, privacy: .public)):\n\(trail, privacy: .public)")
    }

    // MARK: - Helpers

    nonisolated static func formatContext(_ context: [String: Any]) -> String {
        context
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(Self.stringify($0.value))" }
            .joined(separator: " ")
    }

    nonisolated private static func stringify(_ value: Any) -> String {
        switch value {
        case let s as String: return s
        case let e as Error:  return String(describing: e)
        default:              return String(describing: value)
        }
    }
}

// MARK: - CategoryLogger

// warning, error, and critical auto-drop a breadcrumb, debug/info/notice do not
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
        // only override if the key is present, first-launch installs get logging on by default
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
        case app, launch, hang, memory, mainThread, network, ws, auth, session, shield
        case proximity, touchTips, screenTime, cache, push, onboarding, room, profile, ui
        case custom(String)

        init?(rawValue: String) {
            switch rawValue {
            case "app":        self = .app
            case "launch":     self = .launch
            case "hang":       self = .hang
            case "memory":     self = .memory
            case "main_thread": self = .mainThread
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
            case .mainThread: return "main_thread"
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

    func reset() {
        lock.lock()
        storage.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
