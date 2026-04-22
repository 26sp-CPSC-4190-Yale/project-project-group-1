//
//  View+KeyboardDismiss.swift
//  Unplugged.SharedUI.Modifiers
//

import SwiftUI
import UIKit

extension View {
    /// Dismiss the keyboard when the user taps outside a text field.
    ///
    /// Uses a simultaneousGesture (not a plain `.onTapGesture`) so it doesn't swallow
    /// taps that belong to buttons, list rows, etc. — a naive `.onTapGesture` on the
    /// root view would intercept everything and break interactions.
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
