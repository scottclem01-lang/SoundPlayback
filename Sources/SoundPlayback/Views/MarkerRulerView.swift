import AppKit
import SwiftUI

struct MarkerRulerView: View {
    let markers: [TimelineMarker]
    let playheadTime: TimeInterval
    let playStartTime: TimeInterval
    let pixelsPerSecond: Double
    let contentWidth: CGFloat
    let onSeek: (TimeInterval) -> Void
    let onScrub: (TimeInterval) -> Void
    let onMoveMarker: (UUID, TimeInterval) -> Void
    let onDeleteMarker: (UUID) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            SPTheme.panel

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
            .allowsHitTesting(false)

            playheadLine(time: playStartTime, color: SPTheme.playhead.opacity(0.55))
            playheadLine(time: playheadTime, color: SPTheme.playhead)

            ForEach(markers) { marker in
                DraggableMarkerView(
                    marker: marker,
                    pixelsPerSecond: pixelsPerSecond,
                    onMove: { onMoveMarker(marker.id, $0) },
                    onDelete: { onDeleteMarker(marker.id) }
                )
                .offset(x: marker.time * pixelsPerSecond - 10, y: 1)
                .zIndex(5)
            }
        }
        .frame(width: contentWidth, height: SPTheme.rulerHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SPTheme.border)
                .frame(height: 1)
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

    private func time(at x: CGFloat) -> TimeInterval {
        max(0, Double(x) / pixelsPerSecond)
    }

    @ViewBuilder
    private func playheadLine(time: TimeInterval, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 1, height: SPTheme.rulerHeight)
            .offset(x: time * pixelsPerSecond)
            .allowsHitTesting(false)
    }
}

private struct DraggableMarkerView: View {
    let marker: TimelineMarker
    let pixelsPerSecond: Double
    let onMove: (TimeInterval) -> Void
    let onDelete: () -> Void

    @State private var isDragging = false
    @State private var dragTranslation: CGSize = .zero
    @State private var originTime: TimeInterval = 0
    /// Pull this far up before delete-mode engages; below that, Y stays locked.
    private let deleteThreshold: CGFloat = -36

    private var intendingDelete: Bool {
        dragTranslation.height < deleteThreshold
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("\(marker.number)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(SPTheme.canvas)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(intendingDelete ? Color.red.opacity(0.9) : SPTheme.marker)
                .cornerRadius(2)
            Rectangle()
                .fill(intendingDelete ? Color.red.opacity(0.9) : SPTheme.marker)
                .frame(width: 1, height: 10)
        }
        .frame(width: 20)
        .offset(dragTranslation)
        .opacity(intendingDelete ? 0.75 : 1)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        originTime = marker.time
                    }
                    if value.translation.height < deleteThreshold {
                        dragTranslation = value.translation
                    } else {
                        dragTranslation = CGSize(width: value.translation.width, height: 0)
                    }
                }
                .onEnded { value in
                    if value.translation.height < deleteThreshold {
                        onDelete()
                    } else {
                        let newTime = max(0, originTime + Double(value.translation.width) / pixelsPerSecond)
                        onMove(newTime)
                    }
                    dragTranslation = .zero
                    isDragging = false
                }
        )
        .help("Drag to move · pull up to delete")
    }
}
