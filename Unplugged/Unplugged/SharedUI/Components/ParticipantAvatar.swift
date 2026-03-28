//
//  ParticipantAvatar.swift
//  Unplugged.SharedUI.Components
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import SwiftUI

struct ParticipantAvatar: View {
    let name: String
    var size: CGFloat = 48

    private var fontSize: CGFloat {
        switch size {
        case ...40: return 16
        case 41...56: return 20
        default: return 32
        }
    }

    private var fontWeight: Font.Weight {
        size > 56 ? .bold : .semibold
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.surfaceColor)
                .frame(width: size, height: size)

            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: fontSize, weight: fontWeight, design: .rounded))
                .foregroundColor(.tertiaryColor)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        ParticipantAvatar(name: "Sean", size: 40)
        ParticipantAvatar(name: "Michael", size: 48)
        ParticipantAvatar(name: "Sebastian", size: 80)
    }
    .padding()
    .background(Color.primaryColor)
}
