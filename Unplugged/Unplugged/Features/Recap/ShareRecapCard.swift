import SwiftUI
import UnpluggedShared

struct ShareRecapCard: View {
    let recap: SessionRecapResponse

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingMd) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recap.title ?? "Unplugged Session")
                        .font(.headline)
                        .foregroundStyle(Color.tertiaryColor)
                        .lineLimit(1)
                    Text("UNPLUGGED")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.tertiaryColor.opacity(0.45))
                }
                Spacer()
                Image(systemName: recap.endedEarly ? "clock.badge.exclamationmark.fill" : "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(recap.endedEarly ? Color.destructiveColor : Color.secondaryColor)
            }

            Text(TimeInterval(recap.actualFocusedSeconds).humanReadable)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(Color.tertiaryColor)
                .monospacedDigit()

            HStack(spacing: .spacingSm) {
                capsule("\(recap.participants.count) members", systemImage: "person.2.fill")
                capsule(plannedLabel, systemImage: "timer")
                if let weather = recap.weather {
                    capsule(weatherShortLabel(weather), systemImage: weather.conditionSymbol ?? "cloud.sun.fill")
                }
            }
        }
        .padding(.spacingLg)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadius))
    }

    private var plannedLabel: String {
        guard let duration = recap.durationSeconds else { return "Unlimited" }
        return TimeInterval(duration).humanReadable
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primaryColor.opacity(0.35))
            .clipShape(Capsule())
    }
}
