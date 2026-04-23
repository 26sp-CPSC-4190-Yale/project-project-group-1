import SwiftUI

struct DurationValue: Equatable {
    var hours: Int
    var minutes: Int
    var isUnlimited: Bool

    // Unlimited rides the server's 24h cap (UI-only shortcut).
    var durationSeconds: Int {
        isUnlimited ? 24 * 60 * 60 : (hours * 60 + minutes) * 60
    }
}

struct DurationSection: View {
    @Binding var value: DurationValue

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingMd) {
            Text("DURATION")
                .font(.footnote)
                .tracking(2)
                .foregroundStyle(Color.tertiaryColor.opacity(0.4))

            WheelDurationPicker(hours: $value.hours, minutes: $value.minutes)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(Color.surfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(value.isUnlimited ? 0.35 : 1)
                .allowsHitTesting(!value.isUnlimited)

            UnlimitedRow(isOn: $value.isUnlimited)
        }
    }
}

private struct WheelDurationPicker: View {
    @Binding var hours: Int
    @Binding var minutes: Int

    private static let minuteStep = 5
    private let minuteOptions = Array(stride(from: 0, through: 55, by: minuteStep))

    var body: some View {
        HStack(spacing: 0) {
            Picker("Hours", selection: $hours) {
                ForEach(0..<24, id: \.self) { hour in
                    Text("\(hour) hr").tag(hour)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Picker("Minutes", selection: minutesBinding) {
                ForEach(minuteOptions, id: \.self) { minute in
                    Text("\(minute) min").tag(minute)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
        .colorScheme(.dark)
        .labelsHidden()
    }

    // Snap to the nearest 5-minute step so arbitrary incoming values still
    // map to a valid picker row (otherwise the wheel silently picks "0").
    private var minutesBinding: Binding<Int> {
        Binding(
            get: {
                let step = Self.minuteStep
                return min(55, max(0, (minutes / step) * step))
            },
            set: { minutes = $0 }
        )
    }
}

private struct UnlimitedRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "infinity")
                .font(.body)
                .foregroundStyle(Color.tertiaryColor.opacity(isOn ? 1 : 0.5))
                .frame(width: 24)

            Text("Unlimited")
                .font(.body)
                .foregroundStyle(Color.tertiaryColor)

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.secondaryColor)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, .spacingMd)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
