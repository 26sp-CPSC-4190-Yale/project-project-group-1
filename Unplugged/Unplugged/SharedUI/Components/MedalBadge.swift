import SwiftUI
import UnpluggedShared

struct MedalBadge: View {
    let userMedal: UserMedalResponse

    var body: some View {
        VStack(spacing: .spacingSm) {
            Text(userMedal.medal.icon)
                .font(.system(size: 36))
                .frame(width: 64, height: 64)
                .background(Color.surfaceColor)
                .clipShape(Circle())
            Text(userMedal.medal.name)
                .font(.caption)
                .foregroundStyle(Color.tertiaryColor)
                .lineLimit(1)
                .frame(maxWidth: 80)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(userMedal.medal.name). \(userMedal.medal.description)")
    }
}
