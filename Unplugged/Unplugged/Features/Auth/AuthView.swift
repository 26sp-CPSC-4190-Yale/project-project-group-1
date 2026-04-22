//
//  AuthView.swift
//  Unplugged.Features.Auth
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Bindable var viewModel: AuthViewModel
    @State private var showUsernameLogin = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: .spacingMd) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.tertiaryColor)

                        Text("UNPLUGGED")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.tertiaryColor)
                            .tracking(2)

                        Text("Put your phone down together.")
                            .font(.subheadline)
                            .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    }

                    Spacer()
                    Spacer()

                    VStack(spacing: 12) {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            Task { await viewModel.handleAppleSignInResult(result) }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Google Sign-In: server + view-model plumbing is in place
                        // (AuthController.signInWithGoogle + AuthViewModel.signInWithGoogle),
                        // but the client SDK integration isn't wired up yet. Hiding the
                        // button until it is — shipping a dead "coming soon" button is a
                        // known App Store rejection pattern (Guideline 5.1.1(v)).

                        Button {
                            showUsernameLogin = true
                        } label: {
                            Text("Sign in with username")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.surfaceColor)
                                .foregroundStyle(Color.tertiaryColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        LegalFooter()
                            .padding(.top, .spacingSm)
                    }
                    .padding(.horizontal, .spacingXl)
                    .padding(.bottom, .spacingXl)
                }
            }
            .sheet(isPresented: $showUsernameLogin) {
                UsernameLoginView(viewModel: viewModel)
            }
            .errorAlert($viewModel.errorMessage)
        }
    }
}

#Preview {
    AuthView(viewModel: AuthViewModel())
}
