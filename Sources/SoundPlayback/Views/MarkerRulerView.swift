import AppKit
import SwiftUI

struct MarkerRulerView: View {
    let markers: [TimelineMarker]
    let playheadTime: TimeInterval
    let playStartTime: TimeInterval
    let pixelsPerSecond: Double
    let contentWidth: CGFloat
    /// Added to ruler labels so the left edge can read as something other than 0:00.
    let timelineOrigin: TimeInterval
    let onSeek: (TimeInterval) -> Void
    let onScrub: (TimeInterval) -> Void
    let onMoveMarker: (UUID, TimeInterval) -> Void
    let onDeleteMarker: (UUID) -> Void
    let onSetMarkerNote: (UUID, String) -> Void
    let onNoteEditingChanged: (Bool) -> Void

    private var majorStep: TimeInterval {
        TimeFormat.majorTickStep(pixelsPerSecond: pixelsPerSecond)
    }

    private var majorTimes: [TimeInterval] {
        let step = majorStep
        guard step > 0, contentWidth > 0 else { return [0] }
        let end = Double(contentWidth) / pixelsPerSecond
        var times: [TimeInterval] = []
        var t: TimeInterval = 0
        var i = 0
        while t <= end + 1e-9 {
            times.append(t)
            i += 1
            t = Double(i) * step
            if i > 50_000 { break }
        }
        return times
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SPTheme.panel

            // Every-second ticks span the full gray bar; labels stay at the bottom.
            RulerTicksShape(pixelsPerSecond: pixelsPerSecond)
                .stroke(Color.white.opacity(0.32), lineWidth: 1)
                .allowsHitTesting(false)

            ForEach(Array(majorTimes.enumerated()), id: \.offset) { _, t in
                let x = CGFloat(t * pixelsPerSecond)
                Text(TimeFormat.clock(t + timelineOrigin))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
                    // Keep numbers at the bottom (unchanged vertically).
                    .offset(x: x + 3, y: SPTheme.rulerHeight - 14)
                    .allowsHitTesting(false)
            }

            playheadLine(time: playStartTime, color: SPTheme.playhead.opacity(0.55))
            playheadLine(time: playheadTime, color: SPTheme.playhead)

            ForEach(markers) { marker in
                DraggableMarkerView(
                    marker: marker,
                    pixelsPerSecond: pixelsPerSecond,
                    onMove: { onMoveMarker(marker.id, $0) },
                    onDelete: { onDeleteMarker(marker.id) },
                    onSetNote: { onSetMarkerNote(marker.id, $0) },
                    onNoteEditingChanged: onNoteEditingChanged
                )
                // Stem stays centered on marker.time; note extends to the right.
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

/// One tick per second, full height of the gray ruler bar.
private struct RulerTicksShape: Shape {
    var pixelsPerSecond: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var index = 0
        while true {
            let t = Double(index) // every 1.0s
            let x = t * pixelsPerSecond
            if x > rect.width + 0.5 { break }
            // Top of gray bar → bottom (numbers sit near the bottom, unchanged).
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            index += 1
            if index > 100_000 { break }
        }
        return path
    }
}

private struct DraggableMarkerView: View {
    let marker: TimelineMarker
    let pixelsPerSecond: Double
    let onMove: (TimeInterval) -> Void
    let onDelete: () -> Void
    let onSetNote: (String) -> Void
    let onNoteEditingChanged: (Bool) -> Void

    @State private var isDragging = false
    @State private var dragTranslation: CGSize = .zero
    @State private var originTime: TimeInterval = 0
    @State private var isEditingNote = false
    @State private var draftNote = ""
    @FocusState private var noteFieldFocused: Bool
    /// Pull this far up before delete-mode engages; below that, Y stays locked.
    private let deleteThreshold: CGFloat = -36

    private var intendingDelete: Bool {
        dragTranslation.height < deleteThreshold
    }

    var body: some View {
        HStack(alignment: .top, spacing: 3) {
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
                    .frame(width: 1, height: 12)
            }
            .frame(width: 20)

            noteLabel
        }
        .offset(dragTranslation)
        .opacity(intendingDelete ? 0.75 : 1)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    guard !isEditingNote else { return }
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
                    guard !isEditingNote else { return }
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
        .onTapGesture(count: 2) {
            beginNoteEdit()
        }
        .help("Double-click to label · drag to move · pull up to delete")
    }

    @ViewBuilder
    private var noteLabel: some View {
        if isEditingNote {
            TextField("intro, chorus…", text: $draftNote)
                .font(.system(size: 9, design: .default))
                .textFieldStyle(.plain)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.12))
                .cornerRadius(2)
                .frame(width: 88, alignment: .leading)
                .focused($noteFieldFocused)
                .onSubmit { commitNoteEdit() }
                .onExitCommand { cancelNoteEdit() }
                .onAppear {
                    DispatchQueue.main.async {
                        noteFieldFocused = true
                    }
                }
                .onChange(of: noteFieldFocused) { _, focused in
                    if !focused { commitNoteEdit() }
                }
        } else if !marker.note.isEmpty {
            Text(marker.note)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SPTheme.marker)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .leading)
        }
    }

    private func beginNoteEdit() {
        draftNote = marker.note
        isEditingNote = true
        onNoteEditingChanged(true)
    }

    private func commitNoteEdit() {
        guard isEditingNote else { return }
        let trimmed = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingNote = false
        noteFieldFocused = false
        if trimmed != marker.note {
            onSetNote(trimmed)
        }
        onNoteEditingChanged(false)
    }

    private func cancelNoteEdit() {
        guard isEditingNote else { return }
        isEditingNote = false
        noteFieldFocused = false
        draftNote = marker.note
        onNoteEditingChanged(false)
    }
}
