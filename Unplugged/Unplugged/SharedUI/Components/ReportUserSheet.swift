//
//  ReportUserSheet.swift
//  Unplugged.SharedUI.Components
//

import SwiftUI

/// Sheet that collects a reason category and optional details for reporting a user.
///
/// Required by App Store Guideline 1.2: apps with user-generated interactions must provide
/// a mechanism for reporting objectionable content. Submitted reports are persisted server-side
/// for moderator review; we intentionally do not auto-moderate in-client.
struct ReportUserSheet: View {
    let username: String
    let onSubmit: (_ reason: String, _ details: String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: Reason = .harassment
    @State private var details: String = ""
    @State private var isSubmitting = false

    enum Reason: String, CaseIterable, Identifiable {
        case harassment = "Harassment or bullying"
        case impersonation = "Impersonation"
        case spam = "Spam"
        case inappropriate = "Inappropriate content"
        case other = "Other"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryColor.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: .spacingLg) {
                        VStack(alignment: .leading, spacing: .spacingSm) {
                            Text("Report @\(username)")
                                .font(.title2.bold())
                                .foregroundStyle(Color.tertiaryColor)
                            Text("Your report will be reviewed by the Unplugged team. Blocking the user will also prevent them from contacting you.")
                                .font(.body)
                                .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                        }

                        VStack(alignment: .leading, spacing: .spacingSm) {
                            Text("Reason")
                                .font(.captionFont)
                                .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                            ForEach(Reason.allCases) { reason in
                                Button {
                                    selectedReason = reason
                                } label: {
                                    HStack {
                                        Text(reason.rawValue)
                                            .foregroundStyle(Color.tertiaryColor)
                                        Spacer()
                                        if selectedReason == reason {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Color.secondaryColor)
                                        }
                                    }
                                    .padding(.spacingMd)
                                    .background(Color.surfaceColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VStack(alignment: .leading, spacing: .spacingSm) {
                            Text("Details (optional)")
                                .font(.captionFont)
                                .foregroundStyle(Color.tertiaryColor.opacity(0.6))
                            TextEditor(text: $details)
                                .frame(minHeight: 100)
                                .scrollContentBackground(.hidden)
                                .padding(.spacingSm)
                                .background(Color.surfaceColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.tertiaryColor)
                        }

                        Button {
                            Task {
                                isSubmitting = true
                                await onSubmit(selectedReason.rawValue, details)
                                isSubmitting = false
                                dismiss()
                            }
                        } label: {
                            HStack {
                                if isSubmitting { ProgressView().tint(.white) }
                                Text(isSubmitting ? "Submitting…" : "Submit report")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.destructiveColor.opacity(isSubmitting ? 0.4 : 1))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isSubmitting)

                        Button("Cancel") { dismiss() }
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                    }
                    .padding(.spacingLg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
