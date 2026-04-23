import SwiftUI

struct LegalFooter: View {
    static let termsURL = URL(string: "https://unplugged.name/legal/terms")!
    static let privacyURL = URL(string: "https://unplugged.name/legal/privacy")!

    var body: some View {
        VStack(spacing: 2) {
            Text("By continuing you agree to our")
                .font(.captionFont)
                .foregroundStyle(Color.tertiaryColor.opacity(0.5))
            HStack(spacing: 4) {
                Link("Terms of Service", destination: Self.termsURL)
                Text("and")
                    .foregroundStyle(Color.tertiaryColor.opacity(0.5))
                Link("Privacy Policy", destination: Self.privacyURL)
            }
            .font(.captionFont)
            .tint(Color.tertiaryColor.opacity(0.9))
        }
        .multilineTextAlignment(.center)
    }
}

#Preview {
    LegalFooter()
        .padding()
        .background(Color.primaryColor)
}
