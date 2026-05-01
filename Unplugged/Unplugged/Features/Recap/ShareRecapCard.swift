import SwiftUI
import UIKit
import UnpluggedShared

struct ShareRecapCard: View {
    let recap: SessionRecapResponse

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingSm) {
            if let image = firstMemoryImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 168)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: .cornerRadiusSm))
                    .clipped()
                    .padding(.bottom, 4)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UNPLUGGED")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.tertiaryColor.opacity(0.45))
                    Text(recap.title ?? "Unplugged Session")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.tertiaryColor)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: recap.endedEarly ? "clock.badge.exclamationmark.fill" : "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(recap.endedEarly ? Color.destructiveColor : Color.secondaryColor)
            }

            Text(TimeInterval(recap.actualFocusedSeconds).humanReadable)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(Color.tertiaryColor)
                .monospacedDigit()

            if let description = recap.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color.tertiaryColor.opacity(0.72))
                    .lineLimit(3)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: .spacingSm)], alignment: .leading, spacing: .spacingSm) {
                capsule("\(recap.participants.count) \(recap.participants.count == 1 ? "member" : "members")", systemImage: "person.2.fill")
                capsule(durationChipLabel, systemImage: durationChipSystemImage)
                capsule("\(recap.jailbreaks.count) \(recap.jailbreaks.count == 1 ? "break" : "breaks")", systemImage: "exclamationmark.shield.fill")
                if let weather = recap.weather {
                    capsule(weatherShortLabel(weather), systemImage: weather.conditionSymbol ?? "cloud.sun.fill")
                }
                if recap.latitude != nil, recap.longitude != nil {
                    capsule("Location", systemImage: "location.fill")
                }
            }
            .padding(.top, 2)
        }
        .padding(.spacingMd)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadiusSm))
    }

    private var durationChipLabel: String {
        guard let duration = recap.durationSeconds else {
            return "\(TimeInterval(recap.actualFocusedSeconds).humanReadable) locked"
        }
        return TimeInterval(duration).humanReadable
    }

    private var durationChipSystemImage: String {
        recap.durationSeconds == nil ? "infinity" : "timer"
    }

    private var firstMemoryImage: UIImage? {
        recap.memoryPhotos
            .lazy
            .compactMap(\.thumbnailData)
            .compactMap(UIImage.init(data:))
            .first
    }

    private func weatherShortLabel(_ weather: SessionWeatherSnapshot) -> String {
        if let temp = weather.temperatureFahrenheit {
            return "\(Int(temp.rounded()))°F"
        }
        return weather.summary
    }

    private func capsule(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Color.tertiaryColor.opacity(0.75))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.primaryColor.opacity(0.35))
            .clipShape(Capsule())
    }
}
