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
            SecItemDelete(query as CFDictionary)
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func readToken() -> String? {
        if didLoadToken { return cachedToken }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        didLoadToken = true
        guard status == errSecSuccess, let data = result as? Data else {
            cachedToken = nil
            return nil
        }
        cachedToken = String(data: data, encoding: .utf8)
        return cachedToken
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
            SecItemDelete(query as CFDictionary)
        }
    }

    var isLoggedIn: Bool { readToken() != nil }

    func saveUser(_ user: User) {
        let encoded = try? JSONEncoder().encode(user)
        UserDefaults.standard.set(encoded, forKey: userKey)
    }

    func readUser() -> User? {
        guard let data = UserDefaults.standard.data(forKey: userKey) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    func clearUser() {
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    func saveAuth(_ response: AuthResponse) {
        saveToken(response.token)
        saveUser(response.user)
    }

    func clearAuth() {
        deleteToken()
        clearUser()
        UserDefaults.standard.removeObject(forKey: statsKey)
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    // MARK: - Stats cache

    func saveStats(_ stats: UserStatsResponse) {
        guard let data = try? jsonEncoder.encode(stats) else { return }
        UserDefaults.standard.set(data, forKey: statsKey)
    }

    func readStats() -> UserStatsResponse? {
        guard let data = UserDefaults.standard.data(forKey: statsKey) else { return nil }
        return try? jsonDecoder.decode(UserStatsResponse.self, from: data)
    }

    // MARK: - History cache

    func saveHistory(_ history: [SessionHistoryResponse]) {
        guard let data = try? jsonEncoder.encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    func readHistory() -> [SessionHistoryResponse]? {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return nil }
        return try? jsonDecoder.decode([SessionHistoryResponse].self, from: data)
    }
}
