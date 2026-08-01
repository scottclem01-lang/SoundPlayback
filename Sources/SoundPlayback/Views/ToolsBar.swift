import SwiftUI

struct ToolsBar: View {
    let detectedTempoBPM: Double?
    let onAddIntroClicks: () -> Void
    let onAddThumpTrack: () -> Void
    let onTapTempo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Add Intro Clicks", action: onAddIntroClicks)
            Button("Add Thump Track", action: onAddThumpTrack)

            Divider().frame(height: 16)

            Button("Tap Tempo", action: onTapTempo)
                .help("Play and tap the beat on the trackpad to set tempo")

            if let bpm = detectedTempoBPM {
                Text("\(formatBPM(bpm)) BPM")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SPTheme.accent)
                    .help("Last tapped tempo")
            }

            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(SPTheme.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SPTheme.border)
                .frame(height: 1)
        }
    }

    private func formatBPM(_ bpm: Double) -> String {
        if abs(bpm - bpm.rounded()) < 0.05 {
            return "\(Int(bpm.rounded()))"
        }
        return String(format: "%.1f", bpm)
    }
}
