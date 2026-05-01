import SwiftUI

struct ConfirmationPanel: View {
    enum ActionRole {
        case primary
        case destructive
    }

    @Binding var isPresented: Bool
    let title: String
    let message: String
    let confirmTitle: String
    var cancelTitle = "Cancel"
    var systemImage: String?
    var role: ActionRole = .destructive
    let onConfirm: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VStack(alignment: .leading, spacing: .spacingMd) {
                HStack(alignment: .top, spacing: .spacingSm) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(role == .destructive ? Color.destructiveColor : Color.secondaryColor)
                            .frame(width: 24, height: 24)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.tertiaryColor)
                        Text(message)
                            .font(.captionFont)
                            .foregroundStyle(Color.tertiaryColor.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: .spacingSm) {
                    Spacer(minLength: 0)

                    Button(cancelTitle) {
                        dismiss()
                    }
                    .buttonStyle(GlassPillButtonStyle(tint: .tertiaryColor))

                    confirmButton
                }
            }
            .padding(.spacingMd)
            .background(Color.surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: .cornerRadiusSm))
            .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 10)
            .padding(.horizontal, .spacingMd)
            .padding(.bottom, .spacingMd)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var confirmButton: some View {
        switch role {
        case .primary:
            Button(confirmTitle) {
                confirm()
            }
            .buttonStyle(GlassPillButtonStyle(tint: .secondaryColor))
        case .destructive:
            Button(confirmTitle, role: .destructive) {
                confirm()
            }
            .buttonStyle(GlassPillButtonStyle(tint: .destructiveColor))
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isPresented = false
        }
    }

    private func confirm() {
        dismiss()
        onConfirm()
    }
}

extension View {
    func confirmationPanel(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String = "Cancel",
        systemImage: String? = nil,
        role: ConfirmationPanel.ActionRole = .destructive,
        onConfirm: @escaping () -> Void
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                ConfirmationPanel(
                    isPresented: isPresented,
                    title: title,
                    message: message,
                    confirmTitle: confirmTitle,
                    cancelTitle: cancelTitle,
                    systemImage: systemImage,
                    role: role,
                    onConfirm: onConfirm
                )
                .animation(.easeInOut(duration: 0.18), value: isPresented.wrappedValue)
            }
        }
    }
}
