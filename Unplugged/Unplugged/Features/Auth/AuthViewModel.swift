//
//  AuthViewModel.swift
//  Unplugged.Features.Auth
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

// TODO: Replace mock auth with real AuthAPIService calls; store JWT via LocalCacheService; handle token refresh

import Foundation
import Observation

@MainActor
@Observable
class AuthViewModel {
    var isAuthenticated = false

    func signInWithApple() {
        isAuthenticated = true
    }

    func signInWithGoogle() {
        isAuthenticated = true
    }

    func signOut() {
        isAuthenticated = false
    }
}
