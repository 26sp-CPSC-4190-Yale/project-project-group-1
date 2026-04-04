//
//  AuthViewModel.swift
//  Unplugged.Features.Auth
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class AuthViewModel {
    var isAuthenticated = false
    var isLoading = false
    var errorMessage: String?

    private var authService: AuthAPIService?
    private var cache: LocalCacheService?

    func configure(authService: AuthAPIService, cache: LocalCacheService) {
        self.authService = authService
        self.cache = cache
    }

    func restoreSession() {
        guard let cache else { return }
        if cache.isLoggedIn {
            isAuthenticated = true
        }
    }

    func loginWithUsername(username: String, password: String) async {
        guard let authService, let cache else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await authService.login(username: username, password: password)
            cache.saveAuth(response)
            isAuthenticated = true
        } catch {
            errorMessage = message(for: error)
        }
        isLoading = false
    }

    func registerWithUsername(username: String, password: String) async {
        guard let authService, let cache else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await authService.register(username: username, password: password)
            cache.saveAuth(response)
            isAuthenticated = true
        } catch {
            errorMessage = message(for: error)
        }
        isLoading = false
    }

    func signInWithApple() {
        // Placeholder
    }

    func signInWithGoogle() {
        // Placeholder
    }

    func signOut() {
        cache?.clearAuth()
        isAuthenticated = false
    }

    private func message(for error: Error) -> String {
        switch error {
        case AppError.unauthorized:      return "Invalid username or password."
        case AppError.validationFailed:  return "Username already taken or invalid input."
        case AppError.serverError:       return "Server error. Please try again."
        default:                         return "Something went wrong. Check your connection."
        }
    }
}
