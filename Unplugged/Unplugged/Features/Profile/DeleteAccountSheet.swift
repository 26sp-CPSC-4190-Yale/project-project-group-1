//
//  DeleteAccountSheet.swift
//  Unplugged.Features.Profile
//

import SwiftUI

/// Two-step confirmation sheet for account deletion.
///
/// Requires the user to type "DELETE" exactly and — if they signed in with a password —
/// enter that password. OAuth-only users can submit with an empty password; the server
/// decides whether a password is required and returns 400 if it isn't provided and should have been.
struct DeleteAccountSheet: View {
    /// Called when the user confirms. Runs the delete and signals completion.
    let onConfirm: (_ password: String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typedConfirmation = ""
    @State private var password = ""
    @State private var isDeleting = false

    private var canDelete: Bool {
        typedConfirmation.trimmingCharacters(in: .whitespaces) == "DELETE" && !isDeleting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: .spacingLg) {
                        VStack(alignment: .leading, spacing: .spacingSm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(Color.destructiveColor)
                            Text("Delete your account?")
                                .font(.title2.bold())
                                .foregroundStyle(Color.tertiaryColor)
                            Text("Your profile, friends, and session history will be removed. This can't be undone.")
                                .font(.body)
                                .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                        }

                        VStack(alignment: .leading, spacing: .spacingSm) {
                            Text("Type DELETE to confirm")
                                .font(.captionFont)
                                .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                            TextField("DELETE", text: $typedConfirmation)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .padding(.spacingMd)
                                .background(Color.surfaceColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.tertiaryColor)
                        }

                        VStack(alignment: .leading, spacing: .spacingSm) {
                            Text("Password (leave blank if you signed in with Apple or Google)")
                                .font(.captionFont)
                                .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                            SecureField("", text: $password)
                                .padding(.spacingMd)
                                .background(Color.surfaceColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.tertiaryColor)
                        }

                        Button(role: .destructive) {
                            Task {
                                isDeleting = true
                                await onConfirm(password)
                                isDeleting = false
                            }
                        } label: {
                            HStack {
                                if isDeleting { ProgressView().tint(.white) }
                                Text(isDeleting ? "Deleting…" : "Delete my account")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.destructiveColor.opacity(canDelete ? 1 : 0.4))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(!canDelete)

                        Button("Cancel") { dismiss() }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    }
                    .padding(.spacingLg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
