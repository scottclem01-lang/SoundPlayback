import SwiftUI

struct LevelMeterView: View {
    let levels: [Float]
    let channelCount: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(channelCount, 1), id: \.self) { index in
                meterBar(level: index < levels.count ? levels[index] : 0)
            }
        }
        .frame(width: CGFloat(max(channelCount, 1)) * 10 + 4, height: 28)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.35))
        .cornerRadius(4)
        .help("Output levels")
    }

    private func meterBar(level: Float) -> some View {
        let clamped = max(0, min(1, level))
        return GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 1)
                    .fill(meterColor(clamped))
                    .frame(height: max(1, geo.size.height * CGFloat(clamped)))
            }
        }
        .frame(width: 7)
    }

    private func meterColor(_ level: Float) -> Color {
        if level > 0.9 { return .red }
        if level > 0.7 { return .yellow }
        return SPTheme.accent
    }
}
