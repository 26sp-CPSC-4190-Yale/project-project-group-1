import CoreHaptics
import UIKit

@MainActor
final class HapticsService {
    private var tapFeedback: UIImpactFeedbackGenerator?

    func prepareTap() {
        guard Self.supportsHaptics else { return }

        let feedback = tapFeedback ?? UIImpactFeedbackGenerator(style: .medium)
        tapFeedback = feedback
        feedback.prepare()
    }

    func playTap() {
        guard Self.supportsHaptics else { return }

        tapFeedback?.impactOccurred()
        tapFeedback?.prepare()
    }

    private static let supportsHaptics: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        return CHHapticEngine.capabilitiesForHardware().supportsHaptics
        #endif
    }()
}
