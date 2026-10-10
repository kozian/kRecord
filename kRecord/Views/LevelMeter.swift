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
