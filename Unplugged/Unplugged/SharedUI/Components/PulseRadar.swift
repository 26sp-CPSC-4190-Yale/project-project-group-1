import SwiftUI

struct PulseRadar: View {
    @State private var isPulsing = false
    var size: CGFloat = 200

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.tertiaryColor.opacity(0.3), lineWidth: 1)
                    .frame(width: size, height: size)
                    .scaleEffect(isPulsing ? 1.0 + CGFloat(index) * 0.15 : 0.8)
                    .opacity(isPulsing ? 0 : 0.6)
                    .animation(
                        .easeInOut(duration: 2)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.4),
                        value: isPulsing
                    )
            }
        }
        .onAppear { isPulsing = true }
    }
}

#Preview {
    PulseRadar()
        .padding()
        .background(Color.primaryColor)
}
