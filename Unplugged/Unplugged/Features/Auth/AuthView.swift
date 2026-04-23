import SwiftUI
import AuthenticationServices
import GoogleSignIn

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
                        // do not wrap in clipShape, Apple's AppleIDButton leaks a CGPath through AKDrawAppleIDButtonWithCornerRadius on every re-rasterize
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            Task { await viewModel.handleAppleSignInResult(result) }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 50)

                        Button {
                            Task {
                                guard let rootVC = UIApplication.shared.connectedScenes
                                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                                    .first else { return }
                                if let result = try? await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC),
                                   let idToken = result.user.idToken?.tokenString {
                                    await viewModel.signInWithGoogle(idToken: idToken)
                                }
                            }
                        } label: {
                            HStack(spacing: .spacingSm) {
                                Image(systemName: "g.circle.fill")
                                Text("Sign in with Google").fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.white)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

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
