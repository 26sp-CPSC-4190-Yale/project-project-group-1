import SwiftUI
import UIKit

extension View {
    // simultaneousGesture, not onTapGesture, otherwise the root tap swallows button and row taps
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
    }
}
