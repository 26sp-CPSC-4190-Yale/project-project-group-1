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
        HStack {
            Spacer(minLength: 0)
            configuration.label
            Spacer(minLength: 0)
        }
            .font(.headlineFont)
            .foregroundColor(.primaryColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, .spacingMd)
            .background(Color.tertiaryColor)
            .cornerRadius(.cornerRadius)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Spacer(minLength: 0)
            configuration.label
            Spacer(minLength: 0)
        }
            .font(.headlineFont)
            .foregroundColor(.tertiaryColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, .spacingMd)
            .background(Color.destructiveColor)
            .cornerRadius(.cornerRadius)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
