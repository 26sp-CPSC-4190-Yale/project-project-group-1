import SwiftUI

struct LiquidGlassButtonStyle: ButtonStyle {
    var diameter: CGFloat = 140

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: diameter, height: diameter)
            .background(
                Circle()
                    .fill(Color.surfaceColor.opacity(0.7))
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.15), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AppButtonChrome(
            configuration: configuration,
            foreground: .primaryColor,
            background: .tertiaryColor
        )
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AppButtonChrome(
            configuration: configuration,
            foreground: .tertiaryColor,
            background: .surfaceColor
        )
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AppButtonChrome(
            configuration: configuration,
            foreground: .tertiaryColor,
            background: .destructiveColor
        )
    }
}

struct GlassPillButtonStyle: ButtonStyle {
    var foreground: Color = .tertiaryColor
    var tint: Color = .tertiaryColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.surfaceColor.opacity(0.58))
                    .overlay(
                        Capsule()
                            .fill(tint.opacity(configuration.isPressed ? 0.18 : 0.10))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.tertiaryColor.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 6)
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct AppButtonChrome: View {
    let configuration: ButtonStyle.Configuration
    let foreground: Color
    let background: Color

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            configuration.label
            Spacer(minLength: 0)
        }
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        .foregroundColor(foreground)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, .spacingMd)
        .padding(.vertical, 11)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadiusSm))
        .contentShape(Rectangle())
        .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
