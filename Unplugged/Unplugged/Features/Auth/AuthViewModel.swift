//
//  AuthViewModel.swift
//  Unplugged.Features.Auth
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import AuthenticationServices
import Foundation
import Observation
import UnpluggedShared

@MainActor
@Observable
class AuthViewModel {
    var isAuthenticated = false
    var isLoading = false
    var errorMessage: String?
    private(set) var isConfigured = false

    private var authService: AuthAPIService?
    private var cache: LocalCacheService?
    private var sessionOrchestrator: SessionOrchestrator?

    func configure(authService: AuthAPIService,
                   cache: LocalCacheService,
                   sessionOrchestrator: SessionOrchestrator) {
        self.authService = authService
        self.cache = cache
        self.sessionOrchestrator = sessionOrchestrator
        self.isConfigured = true
    }

    func restoreSession() async {
        guard let cache else { return }
        if await cache.isLoggedInAsync() {
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

    /// Called from the Sign in with Apple button's completion handler.
    func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        guard let authService, let cache else { return }
        switch result {
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "Apple sign-in failed."
        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Apple sign-in produced no identity token."
                return
            }
            let authCodeData = credential.authorizationCode
            let authorizationCode = authCodeData.flatMap { String(data: $0, encoding: .utf8) }
            let fullName: String? = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
                .nilIfEmpty

            isLoading = true
            errorMessage = nil
            do {
                let response = try await authService.signInWithApple(
                    identityToken: identityToken,
                    authorizationCode: authorizationCode,
                    fullName: fullName,
                    email: credential.email
                )
                cache.saveAuth(response)
                isAuthenticated = true
            } catch {
                errorMessage = message(for: error)
            }
            isLoading = false
        }
    }

    /// Google sign-in entry point. Requires the GoogleSignIn SDK to be wired up at the call site
    /// to obtain an ID token; once integrated, pass the resulting idToken here.
    func signInWithGoogle(idToken: String) async {
        guard let authService, let cache else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await authService.signInWithGoogle(idToken: idToken)
            cache.saveAuth(response)
            isAuthenticated = true
        } catch {
            errorMessage = message(for: error)
        }
        isLoading = false
    }

    func signOut() {
        // Close the session WebSocket and stop the watchdog BEFORE clearing auth —
        // the socket authenticates via JWT, so it keeps the user's identity alive
        // on the wire even after clearAuth() runs locally. Without this, the listener
        // loop spins until the TCP connection naturally drops.
        if let orchestrator = sessionOrchestrator {
            Task { await orchestrator.teardown() }
        }
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
