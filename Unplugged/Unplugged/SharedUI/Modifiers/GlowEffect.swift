//
//  GlowEffect.swift
//  Unplugged.SharedUI.Modifiers
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct GlowEffect: ViewModifier {
    var color: Color = .tertiaryColor
    var radius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.6), radius: radius)
            .shadow(color: color.opacity(0.3), radius: radius * 2)
    }
}

extension View {
    func glowEffect(color: Color = .tertiaryColor, radius: CGFloat = 10) -> some View {
        modifier(GlowEffect(color: color, radius: radius))
    }
}
