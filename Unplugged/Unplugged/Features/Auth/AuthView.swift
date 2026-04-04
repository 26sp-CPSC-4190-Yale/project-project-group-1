//
//  AuthView.swift
//  Unplugged.Features.Auth
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI
import AuthenticationServices

struct AuthView: View {
    var viewModel: AuthViewModel
    @State private var showUsernameLogin = false

    var body: some View {
        ZStack {
            Color.primaryColor
                .ignoresSafeArea()

            VStack(spacing: .spacingLg) {
                Spacer()

                Text("UNPLUGGED")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.tertiaryColor)
                    .tracking(2)

                Spacer()

                VStack(spacing: .spacingMd) {
                    // Sign in with Apple
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { _ in
                        viewModel.signInWithApple()
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .cornerRadius(.cornerRadiusSm)

                    // Sign in with Google
                    Button(action: { viewModel.signInWithGoogle() }) {
                        HStack(spacing: .spacingSm) {
                            Image("GoogleLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Sign in with Google")
                                .font(.headlineFont)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.tertiaryColor)
                        .foregroundColor(.primaryColor)
                        .cornerRadius(.cornerRadiusSm)
                    }

                    // Login with username
                    Button("Login with username") {
                        showUsernameLogin = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(height: 50)
                }
                .padding(.horizontal, .spacingXl)
                .padding(.bottom, .spacingXl)
            }
        }
        .sheet(isPresented: $showUsernameLogin) {
            UsernameLoginView(viewModel: viewModel)
        }
    }
}

#Preview {
    AuthView(viewModel: AuthViewModel())
}
