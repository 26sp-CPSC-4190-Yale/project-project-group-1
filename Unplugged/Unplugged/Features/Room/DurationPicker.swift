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

            WheelRow(hours: $value.hours, minutes: $value.minutes)
                .opacity(value.isUnlimited ? 0.35 : 1)
                .allowsHitTesting(!value.isUnlimited)
                .animation(.easeOut(duration: 0.2), value: value.isUnlimited)

            UnlimitedRow(isOn: $value.isUnlimited)
        }
    }
}

private struct WheelRow: View {
    @Binding var hours: Int
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 0) {
            wheel(range: 0...24, selection: $hours,   unit: "hr")
            wheel(range: 0...59, selection: $minutes, unit: "min")
        }
        .frame(height: 180)
        .background(Color.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(hairlines)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .onChange(of: hours) { _, new in if new == 24, minutes != 0 { minutes = 0 } }
    }

    private func wheel(range: ClosedRange<Int>, selection: Binding<Int>, unit: String) -> some View {
        Picker("", selection: selection) {
            ForEach(range, id: \.self) { value in
                HStack(spacing: 6) {
                    Text("\(value)")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.tertiaryColor)
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(Color.tertiaryColor.opacity(0.4))
                        .baselineOffset(2)
                }
                .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
    }

    private var hairlines: some View {
        GeometryReader { geo in
            let rowH: CGFloat = 36
            let midY = geo.size.height / 2
            ZStack(alignment: .top) {
                Color.clear
                Rectangle()
                    .fill(Color.secondaryColor.opacity(0.55))
                    .frame(height: 1)
                    .padding(.horizontal, .spacingMd)
                    .offset(y: midY - rowH / 2)
                Rectangle()
                    .fill(Color.secondaryColor.opacity(0.55))
                    .frame(height: 1)
                    .padding(.horizontal, .spacingMd)
                    .offset(y: midY + rowH / 2 - 1)
            }
        }
        .allowsHitTesting(false)
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
