import AudioToolbox
import Foundation

@MainActor
final class AudioService {
    enum Cue {
        case participantJoined
        case sessionLocked
        case sessionEnded
        case warning
    }

    func play(_ cue: Cue) {
        #if targetEnvironment(simulator)
        return
        #else
        switch cue {
        case .participantJoined:
            AudioServicesPlaySystemSound(1104)
        case .sessionLocked:
            AudioServicesPlaySystemSound(1113)
        case .sessionEnded:
            AudioServicesPlaySystemSound(1057)
        case .warning:
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        #endif
    }
}
