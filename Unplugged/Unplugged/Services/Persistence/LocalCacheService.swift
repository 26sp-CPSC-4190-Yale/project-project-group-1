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

    func saveToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey
        ]
        SecItemDelete(query as CFDictionary)
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
    }
}
