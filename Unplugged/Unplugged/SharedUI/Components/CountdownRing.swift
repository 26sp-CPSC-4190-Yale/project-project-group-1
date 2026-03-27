//
//  CountdownRing.swift
//  Unplugged.SharedUI.Components
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct CountdownRing: View {
    var progress: Double = 0
    var size: CGFloat = 200
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.surfaceColor, lineWidth: lineWidth)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.tertiaryColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
        }
    }
}

#Preview {
    CountdownRing(progress: 0.65)
        .padding()
        .background(Color.primaryColor)
}
