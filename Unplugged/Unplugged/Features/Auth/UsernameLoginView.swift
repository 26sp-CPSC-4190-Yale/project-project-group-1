import SwiftUI

struct UsernameLoginView: View {
    var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var isRegistering = false

    var body: some View {
        ZStack {
            Color.primaryColor.ignoresSafeArea()

            VStack(spacing: .spacingLg) {
                Text(isRegistering ? "Create Account" : "Sign In")
                    .font(.titleFont)
                    .foregroundColor(.tertiaryColor)

                VStack(spacing: .spacingMd) {
                    TextField("Username", text: $username)
                        .textFieldStyle(UnpluggedTextFieldStyle())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Password", text: $password)
                        .textFieldStyle(UnpluggedTextFieldStyle())
                }



                Button(isRegistering ? "Create Account" : "Sign In") {
                    Task {
                        if isRegistering {
                            await viewModel.registerWithUsername(username: username, password: password)
                        } else {
                            await viewModel.loginWithUsername(username: username, password: password)
                        }
                        if viewModel.isAuthenticated { dismiss() }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(username.isEmpty || password.isEmpty || viewModel.isLoading)

                Button(isRegistering ? "Already have an account? Sign in" : "No account? Create one") {
                    isRegistering.toggle()
                    viewModel.errorMessage = nil
                }
                .font(.captionFont)
                .foregroundColor(.secondaryColor)
            }
            .padding(.horizontal, .spacingXl)

            if viewModel.isLoading {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView()
                    .tint(.tertiaryColor)
                    .scaleEffect(1.5)
            }
        }
        .alert(
            "Authentication Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) { viewModel.errorMessage = nil } },
            message: { Text(viewModel.errorMessage ?? "An error occurred.") }
        )
    }
}

private struct UnpluggedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.bodyFont)
            .foregroundColor(.tertiaryColor)
            .padding(.spacingMd)
            .background(Color.surfaceColor)
            .cornerRadius(.cornerRadiusSm)
    }
}

#Preview {
    UsernameLoginView(viewModel: AuthViewModel())
}
