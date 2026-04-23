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
    private var userService: UserAPIService?
    private var cache: LocalCacheService?
    private var sessionOrchestrator: SessionOrchestrator?
    // The observer is only touched from MainActor in `installAuthInvalidatedObserver`,
    // but `deinit` on a MainActor class is nonisolated, so the property itself
    // is marked `nonisolated(unsafe)` — we only write it once, during configure().
    // The closure captures `[weak self]` so the observer surviving the vm's dealloc
    // is harmless (the callback no-ops on a nil self and NotificationCenter drops it
    // the next time it tries to message the long-dead observer).
    private nonisolated(unsafe) var authInvalidatedObserver: NSObjectProtocol?

    deinit {
        if let observer = authInvalidatedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func configure(authService: AuthAPIService,
                   userService: UserAPIService,
                   cache: LocalCacheService,
                   sessionOrchestrator: SessionOrchestrator) {
        self.authService = authService
        self.userService = userService
        self.cache = cache
        self.sessionOrchestrator = sessionOrchestrator
        self.isConfigured = true
        installAuthInvalidatedObserver()
    }

    /// Listen for `unpluggedAuthDidInvalidate`, fired by APIClient when any request
    /// returns 401. This is the fallback re-auth path until a real refresh-token
    /// endpoint exists: drop the user back to the sign-in screen immediately so
    /// they aren't stuck retrying with a dead token.
    private func installAuthInvalidatedObserver() {
        guard authInvalidatedObserver == nil else { return }
        authInvalidatedObserver = NotificationCenter.default.addObserver(
            forName: .unpluggedAuthDidInvalidate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isAuthenticated else { return }
                AppLogger.auth.warning("auth invalidated by server — signing out")
                self.signOut()
            }
        }
    }

    func restoreSession() async {
        guard let cache else {
            AppLogger.auth.warning("restoreSession called before configure()")
            return
        }
        guard await cache.isLoggedInAsync() else { return }
        if cache.readUser() == nil, let userService {
            do {
                let user = try await userService.getMe()
                cache.saveUser(user)
            } catch {
                // Token was cached but /me failed. Could be 401 (token expired
                // while app was backgrounded) or network issue. Log so we can
                // distinguish "user never signed in" from "user silently
                // bounced out on launch" in support reports.
                AppLogger.auth.error("restoreSession: getMe failed — proceeding without cached user", error: error)
            }
        }
        isAuthenticated = true
    }

    func loginWithUsername(username: String, password: String) async {
        guard let authService, let cache else {
            AppLogger.auth.warning("loginWithUsername called before configure()")
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await authService.login(username: username, password: password)
            cache.saveAuth(response)
            isAuthenticated = true
        } catch {
            AppLogger.auth.warning("username login failed", context: ["error": String(describing: error)])
            errorMessage = message(for: error)
        }
        isLoading = false
    }

    func registerWithUsername(username: String, password: String) async {
        guard let authService, let cache else {
            AppLogger.auth.warning("registerWithUsername called before configure()")
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await authService.register(username: username, password: password)
            cache.saveAuth(response)
            isAuthenticated = true
        } catch {
            AppLogger.auth.warning("username registration failed", context: ["error": String(describing: error)])
            errorMessage = message(for: error)
        }
        isLoading = false
    }

    /// Called from the Sign in with Apple button's completion handler.
    func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        guard let authService, let cache else {
            AppLogger.auth.warning("handleAppleSignInResult called before configure()")
            return
        }
        switch result {
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code == .canceled { return }
            AppLogger.auth.error("Apple sign-in returned failure", error: err)
            errorMessage = "Apple sign-in failed."
        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                AppLogger.auth.error(
                    "Apple credential missing identity token",
                    context: [
                        "credential_type": String(describing: type(of: auth.credential)),
                        "has_token_data": (auth.credential as? ASAuthorizationAppleIDCredential)?.identityToken != nil
                    ]
                )
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
                AppLogger.auth.error("Apple sign-in API failed", error: error)
                errorMessage = message(for: error)
            }
            isLoading = false
        }
    }

    /// Google sign-in entry point. Requires the GoogleSignIn SDK to be wired up at the call site
    /// to obtain an ID token; once integrated, pass the resulting idToken here.
    func signInWithGoogle(idToken: String) async {
        guard let authService, let cache else {
            AppLogger.auth.warning("signInWithGoogle called before configure()")
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await authService.signInWithGoogle(idToken: idToken)
            cache.saveAuth(response)
            isAuthenticated = true
        } catch {
            AppLogger.auth.error("Google sign-in API failed", error: error)
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
        // APIClient now throws `APIError`, which conforms to LocalizedError and
        // carries the server's `reason` string. Surface that directly where
        // available (e.g. "Username already taken"); fall back to a kind-based
        // default for errors with no reason (network / server 500).
        if let apiError = error as? APIError {
            if let reason = apiError.reason, !reason.isEmpty {
                switch apiError.kind {
                case .unauthorized where apiError.status == 401 && apiError.reason == "Unauthorized":
                    return "Invalid username or password."
                default:
                    return reason
                }
            }
            switch apiError.kind {
            case .unauthorized:                 return "Invalid username or password."
            case .validationFailed:             return "Username already taken or invalid input."
            case .rateLimited:                  return "Too many attempts. Please wait and try again."
            case .network:                      return "Connection problem. Check your internet and try again."
            case .serverError:                  return "Server error. Please try again."
            case .notFound, .sessionFull,
                 .sessionNotActive,
                 .screenTimePermissionRevoked:
                return apiError.kind.rawValue
            }
        }
        switch error {
        case AppError.unauthorized:      return "Invalid username or password."
        case AppError.validationFailed:  return "Username already taken or invalid input."
        case AppError.serverError:       return "Server error. Please try again."
        case AppError.rateLimited:       return "Too many attempts. Please wait and try again."
        case AppError.network:           return "Connection problem. Check your internet and try again."
        default:
            let description = error.localizedDescription
            return description.isEmpty ? "Something went wrong. Check your connection." : description
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
