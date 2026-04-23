import SwiftUI

struct CountdownView: View {
    let endsAt: Date
    @State private var viewModel = CountdownViewModel()

    var body: some View {
        VStack(spacing: .spacingLg) {
            ZStack {
                CountdownRing(progress: viewModel.progress, size: 220, lineWidth: 10)
                VStack(spacing: .spacingSm) {
                    Text(viewModel.remaining.hms)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundColor(.tertiaryColor)
                        .monospacedDigit()
                    Text("remaining")
                        .font(.captionFont)
                        .foregroundColor(.tertiaryColor.opacity(0.6))
                }
            }
        }
        .onAppear { viewModel.start(endsAt: endsAt) }
        .onDisappear { viewModel.stop() }
        .onChange(of: endsAt) { _, newValue in viewModel.start(endsAt: newValue) }
    }
}

#Preview {
    CountdownView(endsAt: Date().addingTimeInterval(300))
        .padding()
        .background(Color.primaryColor)
}
