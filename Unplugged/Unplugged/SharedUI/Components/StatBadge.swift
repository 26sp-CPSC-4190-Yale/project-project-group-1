//
//  StatBadge.swift
//  Unplugged.SharedUI.Components
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct StatBadge: View {
    let value: String
    let label: String
    var valueSize: CGFloat = 48
    var labelColor: Color = .tertiaryColor.opacity(0.7)

    var body: some View {
        VStack(spacing: .spacingSm) {
            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .foregroundColor(.tertiaryColor)
            Text(label)
                .font(.captionFont)
                .foregroundColor(labelColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacingLg)
        .background(
            RoundedRectangle(cornerRadius: .cornerRadius)
                .fill(Color.surfaceColor.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: .cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.1), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
        )
    }
}

#Preview {
    HStack(spacing: 16) {
        StatBadge(value: "32", label: "Hours Focused")
        StatBadge(value: "1st", label: "Among Friends")
    }
    .padding()
    .background(Color.primaryColor)
}
