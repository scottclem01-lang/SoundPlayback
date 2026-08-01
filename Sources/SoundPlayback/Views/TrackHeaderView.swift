import SwiftUI

struct TrackHeaderView: View {
    @Binding var track: Track
    let availableOutputs: Int
    let onToggleOutput: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(track.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SPTheme.textPrimary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Slider(value: $track.volume, in: 0...1)
                    .controlSize(.mini)
                Text("\(Int(track.volume * 100))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SPTheme.textSecondary)
                    .frame(width: 28, alignment: .trailing)
            }

            HStack(spacing: 6) {
                ToggleChip(title: "M", isOn: $track.isMuted, activeColor: .orange)
                ToggleChip(title: "S", isOn: $track.isSoloed, activeColor: .yellow)
                ForEach(1...4, id: \.self) { channel in
                    let enabled = channel <= availableOutputs
                    let isOn = track.outputMask.contains(.channel(channel))
                    Button {
                        onToggleOutput(channel)
                    } label: {
                        Text("\(channel)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .frame(width: 18, height: 18)
                            .background(isOn && enabled ? SPTheme.accent.opacity(0.85) : Color.white.opacity(0.08))
                            .foregroundStyle(enabled ? SPTheme.textPrimary : SPTheme.textSecondary.opacity(0.35))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(SPTheme.border, lineWidth: 1)
                            )
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                }
            }
        }
        .padding(10)
        .frame(width: SPTheme.headerWidth, height: SPTheme.trackHeight, alignment: .topLeading)
        .background(SPTheme.panel)
        .overlay(Rectangle().stroke(SPTheme.border, lineWidth: 1))
    }
}

private struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool
    var activeColor: Color

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(width: 18, height: 18)
                .background(isOn ? activeColor.opacity(0.85) : Color.white.opacity(0.08))
                .foregroundStyle(SPTheme.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(SPTheme.border, lineWidth: 1)
                )
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
}
