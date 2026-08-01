import SwiftUI

struct TimelineLaneView: View {
    let track: Track
    let pixelsPerSecond: Double
    let contentWidth: CGFloat
    let playheadTime: TimeInterval

    var body: some View {
        ZStack(alignment: .topLeading) {
            SPTheme.trackLane

            ForEach(track.clips) { clip in
                ClipView(clip: clip, pixelsPerSecond: pixelsPerSecond)
                    .offset(x: clip.timelineStart * pixelsPerSecond, y: 8)
            }

            Rectangle()
                .fill(SPTheme.playhead)
                .frame(width: 1, height: SPTheme.trackHeight)
                .offset(x: playheadTime * pixelsPerSecond)
        }
        .frame(width: contentWidth, height: SPTheme.trackHeight)
        .overlay(Rectangle().stroke(SPTheme.border, lineWidth: 1))
    }
}

struct ClipView: View {
    let clip: AudioClip
    let pixelsPerSecond: Double

    var body: some View {
        let width = max(8, clip.duration * pixelsPerSecond)
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(SPTheme.clipFill)
            // Placeholder waveform bars until sample peaks are generated
            HStack(spacing: 1) {
                ForEach(0..<max(1, Int(width / 3)), id: \.self) { i in
                    let h = 8 + Double((i * 37) % 20)
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 2, height: h)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            Text(clip.sourceURL.deletingPathExtension().lastPathComponent)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SPTheme.textPrimary)
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: width, height: SPTheme.trackHeight - 16)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}
