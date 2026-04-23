//
//  LocalCacheService.swift
//  Unplugged.Services.Persistence
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Security
import UnpluggedShared

/// Thread-safe cache for auth token and cached user. Mutable state is guarded by
/// `stateLock`; the keychain I/O runs on `keychainQueue` so callers never block
/// on `SecItemCopyMatching`. The class is reachable from any actor (APIClient is
/// a struct, orchestrator is MainActor, keychain callbacks come off a dispatch
/// queue), so it is `@unchecked Sendable` with the lock doing the heavy lifting.
final class LocalCacheService: @unchecked Sendable {
    private let tokenKey = "unplugged.auth.token"
    private let userKey = "unplugged.cached.user"
    private let statsKey = "unplugged.cached.stats"
    private let historyKey = "unplugged.cached.history"
    private let keychainQueue = DispatchQueue(label: "unplugged.keychain", qos: .userInitiated)

    /// Protects `cachedToken`, `didLoadToken`, and `cachedUser`. Held only for in-memory
    /// mutations — keychain / UserDefaults I/O happens outside the lock.
    private let stateLock = NSLock()
    private var cachedToken: String?
    private var didLoadToken = false
    private var cachedUser: User?

    private let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func saveToken(_ token: String) {
        stateLock.lock()
        cachedToken = token
        didLoadToken = true
        stateLock.unlock()

        let key = tokenKey
        keychainQueue.async {
            let data = Data(token.utf8)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecValueData as String: data
            ]
            let deleteStatus = SecItemDelete(query as CFDictionary)
            if deleteStatus != errSecSuccess, deleteStatus != errSecItemNotFound {
                AppLogger.cache.warning("SecItemDelete before save non-fatal failure", context: ["status": deleteStatus])
            }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus != errSecSuccess {
                // Loss of keychain write means the user will be silently
                // signed out on next cold launch — that's bad enough to warrant
                // a fault-level log.
                AppLogger.cache.critical("SecItemAdd(token) failed", context: ["status": addStatus])
            }
        }
    }

    /// Async variant: performs the keychain read on a background queue so the caller
    /// never blocks on `SecItemCopyMatching`. `SecItemCopyMatching` can take hundreds
    /// of milliseconds on a cold keychain — calling it from the MainActor freezes the
    /// first frame, which then cascades into every subsequent interaction feeling slow.
    func readTokenAsync() async -> String? {
        stateLock.lock()
        if didLoadToken {
            let t = cachedToken
            stateLock.unlock()
            return t
        }
        stateLock.unlock()

        let key = tokenKey
        let token: String? = await withCheckedContinuation { cont in
            keychainQueue.async {
                cont.resume(returning: Self.keychainReadToken(key: key))
            }
        }

        stateLock.lock()
        // Another writer may have raced us (saveToken / clearAuth). If they already
        // populated state, honor that instead of clobbering with the possibly-stale
        // keychain value we just fetched.
        if !didLoadToken {
            cachedToken = token
            didLoadToken = true
        }
        let result = cachedToken
        stateLock.unlock()
        return result
    }

    /// Kick off an asynchronous keychain prewarm. Safe to call at app launch from the
    /// MainActor — the actual `SecItemCopyMatching` runs on `keychainQueue`.
    func prewarmToken() {
        stateLock.lock()
        if didLoadToken {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        let key = tokenKey
        keychainQueue.async { [weak self] in
            guard let self else { return }
            let token = Self.keychainReadToken(key: key)
            self.stateLock.lock()
            if !self.didLoadToken {
                self.cachedToken = token
                self.didLoadToken = true
            }
            self.stateLock.unlock()
        }
    }

    private static func keychainReadToken(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            // Expected on a fresh install — not worth logging.
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            AppLogger.cache.error(
                "SecItemCopyMatching(token) failed",
                context: ["status": status]
            )
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Fast in-memory snapshot for request construction. This intentionally does not
    /// fall back to Keychain; API paths must not block the UI on SecItemCopyMatching.
    /// Returns nil if the prewarm has not yet completed — callers on cold paths should
    /// await `readTokenAsync()` instead.
    func readCachedToken() -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cachedToken
    }

    func deleteToken() {
        stateLock.lock()
        cachedToken = nil
        didLoadToken = true
        stateLock.unlock()

        let key = tokenKey
        keychainQueue.async {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess, status != errSecItemNotFound {
                AppLogger.cache.warning("SecItemDelete(token) failed", context: ["status": status])
            }
        }
    }

    /// Async login state check. The sync variant was removed because it triggered
    /// `SecItemCopyMatching` on the MainActor, which can stall for hundreds of ms
    /// on a cold keychain. Callers must `await` this and gate UI transitions off it.
    func isLoggedInAsync() async -> Bool {
        await readTokenAsync() != nil
    }

    func saveUser(_ user: User) {
        stateLock.lock()
        cachedUser = user
        stateLock.unlock()
        do {
            let encoded = try jsonEncoder.encode(user)
            UserDefaults.standard.set(encoded, forKey: userKey)
        } catch {
            AppLogger.cache.error("user encode failed — cached user not persisted", error: error)
        }
    }

    func readUser() -> User? {
        stateLock.lock()
        if let cached = cachedUser {
            stateLock.unlock()
            return cached
        }
        stateLock.unlock()

        guard let data = UserDefaults.standard.data(forKey: userKey) else { return nil }
        do {
            let user = try jsonDecoder.decode(User.self, from: data)
            stateLock.lock()
            // A concurrent saveUser may have raced us. Prefer the newer value.
            if cachedUser == nil {
                cachedUser = user
            }
            let result = cachedUser
            stateLock.unlock()
            return result
        } catch {
            // Schema drift: old User shape saved, new app version trying to
            // decode it. Log and clear so next sign-in writes a fresh copy.
            AppLogger.cache.error("user decode failed — clearing cached value", error: error, context: ["bytes": data.count])
            UserDefaults.standard.removeObject(forKey: userKey)
            return nil
        }
    }

    func clearUser() {
        stateLock.lock()
        cachedUser = nil
        stateLock.unlock()
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    func saveAuth(_ response: AuthResponse) {
        saveToken(response.token)
        saveUser(response.user)
    }

    func clearAuth() {
        stateLock.lock()
        cachedToken = nil
        didLoadToken = true
        cachedUser = nil
        stateLock.unlock()

        let key = tokenKey
        keychainQueue.async {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess, status != errSecItemNotFound {
                AppLogger.cache.warning("SecItemDelete during clearAuth failed", context: ["status": status])
            }
        }
        UserDefaults.standard.removeObject(forKey: userKey)
        UserDefaults.standard.removeObject(forKey: statsKey)
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    // MARK: - Stats cache

    func saveStats(_ stats: UserStatsResponse) {
        do {
            let data = try jsonEncoder.encode(stats)
            UserDefaults.standard.set(data, forKey: statsKey)
        } catch {
            AppLogger.cache.error("stats encode failed", error: error)
        }
    }

    func readStats() -> UserStatsResponse? {
        guard let data = UserDefaults.standard.data(forKey: statsKey) else { return nil }
        do {
            return try jsonDecoder.decode(UserStatsResponse.self, from: data)
        } catch {
            AppLogger.cache.error("stats decode failed — clearing cached value", error: error, context: ["bytes": data.count])
            UserDefaults.standard.removeObject(forKey: statsKey)
            return nil
        }
    }

    // MARK: - History cache

    func saveHistory(_ history: [SessionHistoryResponse]) {
        do {
            let data = try jsonEncoder.encode(history)
            UserDefaults.standard.set(data, forKey: historyKey)
        } catch {
            AppLogger.cache.error("history encode failed", error: error)
        }
    }

    func readHistory() -> [SessionHistoryResponse]? {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return nil }
        do {
            return try jsonDecoder.decode([SessionHistoryResponse].self, from: data)
        } catch {
            AppLogger.cache.error("history decode failed — clearing cached value", error: error, context: ["bytes": data.count])
            UserDefaults.standard.removeObject(forKey: historyKey)
            return nil
        }
    }
}
