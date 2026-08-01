import SwiftUI

struct MarkerRulerView: View {
    let markers: [TimelineMarker]
    let playheadTime: TimeInterval
    let playStartTime: TimeInterval
    let pixelsPerSecond: Double
    let contentWidth: CGFloat
    let onSeek: (TimeInterval) -> Void
    let onScrub: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                SPTheme.panel

                // Light tick marks every second
                Canvas { context, size in
                    let step = max(1.0, floor(40 / pixelsPerSecond))
                    var t = 0.0
                    while t * pixelsPerSecond < size.width {
                        let x = t * pixelsPerSecond
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height - 8))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(.white.opacity(0.2)), lineWidth: 1)
                        t += step
                    }
                }

                ForEach(markers) { marker in
                    let x = marker.time * pixelsPerSecond
                    VStack(spacing: 0) {
                        Text("\(marker.number)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(SPTheme.canvas)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(SPTheme.marker)
                            .cornerRadius(2)
                        Rectangle()
                            .fill(SPTheme.marker)
                            .frame(width: 1, height: 10)
                    }
                    .offset(x: x - 6, y: 2)
                }

                // Play-start diamond
                playheadLine(time: playStartTime, color: SPTheme.playhead.opacity(0.55), height: geo.size.height)

                // Live playhead
                playheadLine(time: playheadTime, color: SPTheme.playhead, height: geo.size.height)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onScrub(time(at: value.location.x))
                    }
                    .onEnded { value in
                        onSeek(time(at: value.location.x))
                    }
            )
        }
        .frame(width: contentWidth, height: SPTheme.rulerHeight)
    }

    private func time(at x: CGFloat) -> TimeInterval {
        max(0, Double(x) / pixelsPerSecond)
    }

    @ViewBuilder
    private func playheadLine(time: TimeInterval, color: Color, height: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 1, height: height)
            .offset(x: time * pixelsPerSecond)
    }
}
