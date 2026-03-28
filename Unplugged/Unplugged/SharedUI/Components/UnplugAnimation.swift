//
//  UnplugAnimation.swift
//  Unplugged.SharedUI.Components
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct UnplugAnimation: View {
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "wifi.slash")
            .font(.system(size: 48))
            .foregroundColor(.tertiaryColor)
            .rotationEffect(.degrees(isAnimating ? 10 : -10))
            .animation(
                .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

#Preview {
    UnplugAnimation()
        .padding()
        .background(Color.primaryColor)
}
