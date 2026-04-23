//
//  LocalCacheService.swift
//  Unplugged.Services.Persistence
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Security
import UnpluggedShared

class LocalCacheService {
    private let tokenKey = "unplugged.auth.token"
    private let userKey = "unplugged.cached.user"
    private let statsKey = "unplugged.cached.stats"
    private let historyKey = "unplugged.cached.history"
    private let keychainQueue = DispatchQueue(label: "unplugged.keychain", qos: .userInitiated)
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
        cachedToken = token
        didLoadToken = true
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

    func readToken() -> String? {
        if didLoadToken { return cachedToken }
        let token = Self.keychainReadToken(key: tokenKey)
        cachedToken = token
        didLoadToken = true
        return token
    }

    /// Async variant: performs the keychain read on a background queue so the caller
    /// never blocks on `SecItemCopyMatching`. `SecItemCopyMatching` can take hundreds
    /// of milliseconds on a cold keychain — calling it from the MainActor freezes the
    /// first frame, which then cascades into every subsequent interaction feeling slow.
    func readTokenAsync() async -> String? {
        if didLoadToken { return cachedToken }
        let key = tokenKey
        let token: String? = await withCheckedContinuation { cont in
            keychainQueue.async {
                cont.resume(returning: Self.keychainReadToken(key: key))
            }
        }
        cachedToken = token
        didLoadToken = true
        return token
    }

    /// Kick off an asynchronous keychain prewarm. Safe to call at app launch from the
    /// MainActor — the actual `SecItemCopyMatching` runs on `keychainQueue`.
    func prewarmToken() {
        guard !didLoadToken else { return }
        let key = tokenKey
        keychainQueue.async { [weak self] in
            let token = Self.keychainReadToken(key: key)
            DispatchQueue.main.async {
                guard let self, !self.didLoadToken else { return }
                self.cachedToken = token
                self.didLoadToken = true
            }
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
    func readCachedToken() -> String? {
        cachedToken
    }

    func deleteToken() {
        cachedToken = nil
        didLoadToken = true
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

    var isLoggedIn: Bool { readToken() != nil }

    /// Async version of `isLoggedIn` that avoids blocking the MainActor on the keychain.
    func isLoggedInAsync() async -> Bool {
        await readTokenAsync() != nil
    }

    func saveUser(_ user: User) {
        cachedUser = user
        do {
            let encoded = try jsonEncoder.encode(user)
            UserDefaults.standard.set(encoded, forKey: userKey)
        } catch {
            AppLogger.cache.error("user encode failed — cached user not persisted", error: error)
        }
    }

    func readUser() -> User? {
        if let cachedUser { return cachedUser }
        guard let data = UserDefaults.standard.data(forKey: userKey) else { return nil }
        do {
            let user = try jsonDecoder.decode(User.self, from: data)
            cachedUser = user
            return user
        } catch {
            // Schema drift: old User shape saved, new app version trying to
            // decode it. Log and clear so next sign-in writes a fresh copy.
            AppLogger.cache.error("user decode failed — clearing cached value", error: error, context: ["bytes": data.count])
            UserDefaults.standard.removeObject(forKey: userKey)
            return nil
        }
    }

    func clearUser() {
        cachedUser = nil
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    func saveAuth(_ response: AuthResponse) {
        saveToken(response.token)
        saveUser(response.user)
    }

    func clearAuth() {
        cachedToken = nil
        didLoadToken = true
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
        clearUser()
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
