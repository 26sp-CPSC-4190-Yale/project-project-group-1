import SwiftUI
import UnpluggedShared

struct UsernameLoginView: View {
    @Bindable var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var isRegistering = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: .spacingLg) {
                        VStack(spacing: .spacingSm) {
                            Text(isRegistering ? "Create Account" : "Welcome Back")
                                .font(.title.bold())
                                .foregroundStyle(Color.tertiaryColor)

                            Text(isRegistering ? "Choose a username and password" : "Sign in to your account")
                                .font(.subheadline)
                                .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                        }
                        .padding(.top, .spacingXl)

                        VStack(spacing: .spacingMd) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Username")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                                TextField("", text: $username, prompt: Text("Enter username").foregroundStyle(Color.tertiaryColor.opacity(0.3)))
                                    .font(.body)
                                    .foregroundStyle(Color.tertiaryColor)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .padding(14)
                                    .background(Color.surfaceColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Password")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                                SecureField("", text: $password, prompt: Text("Enter password").foregroundStyle(Color.tertiaryColor.opacity(0.3)))
                                    .font(.body)
                                    .foregroundStyle(Color.tertiaryColor)
                                    .padding(14)
                                    .background(Color.surfaceColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                if isRegistering {
                                    Text(InputValidation.passwordRequirementsMessage)
                                        .font(.caption)
                                        .foregroundStyle(Color.tertiaryColor.opacity(0.5))
                                        .padding(.top, 2)
                                }
                            }
                        }

                        Button {
                            Task {
                                if isRegistering {
                                    await viewModel.registerWithUsername(username: username, password: password)
                                } else {
                                    await viewModel.loginWithUsername(username: username, password: password)
                                }
                                if viewModel.isAuthenticated { dismiss() }
                            }
                        } label: {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.primaryColor)
                            } else {
                                Text(isRegistering ? "Create Account" : "Sign In")
                            }
                        }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(username.isEmpty || password.isEmpty ? Color.tertiaryColor.opacity(0.3) : Color.tertiaryColor)
                        .foregroundStyle(Color.primaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(username.isEmpty || password.isEmpty || viewModel.isLoading)

                        Button(isRegistering ? "Already have an account? Sign in" : "Don't have an account? Create one") {
                            withAnimation { isRegistering.toggle() }
                            viewModel.errorMessage = nil
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryColor)

                        // App Store guideline 5.1.1(v) + 3.1.2: ToS and Privacy Policy
                        // must be accessible in-app, not just on the App Store listing,
                        // and must appear before account creation.
                        LegalFooter()
                            .padding(.top, .spacingSm)
                    }
                    .padding(.horizontal, .spacingLg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.tertiaryColor)
                }
            }
        }
        .errorAlert($viewModel.errorMessage)
        .presentationDetents([.large])
    }
}

#Preview {
    UsernameLoginView(viewModel: AuthViewModel())
}
