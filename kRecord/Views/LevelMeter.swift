import SwiftUI

/// A horizontal level bar; `value` is 0...1 (see `AudioLevel.meterValue`).
struct LevelMeter: View {
    let value: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                LinearGradient(colors: [.green, .green, .yellow, .red], startPoint: .leading, endPoint: .trailing)
                    .mask(alignment: .leading) {
                        Capsule().frame(width: max(proxy.size.width * CGFloat(min(max(value, 0), 1)), 0))
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.12), value: value)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(min(max(value, 0), 1) * 100)) percent"))
    }
}

/// A level bar with a checkbox above it that turns its source on or off for the next recording.
struct SourceLevelMeter: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    let isLocked: Bool
    let value: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.checkbox)
                .font(.caption)
                .disabled(isLocked)
            LevelMeter(value: value)
                .opacity(isOn ? 1 : 0.4)
        }
    }
}
