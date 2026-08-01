import AppKit
import SwiftUI

struct TimelineLaneView: View {
    let track: Track
    let trackIndex: Int
    let allTracks: [Track]
    let peaksProvider: (AudioClip) -> [Float]
    let pixelsPerSecond: Double
    let contentWidth: CGFloat
    let playheadTime: TimeInterval
    let selectedClipIDs: Set<UUID>
    let snapMoveStart: (AudioClip, TimeInterval) -> TimeInterval
    let snapTrimStart: (AudioClip, TimeInterval) -> TimeInterval
    let snapTrimEnd: (AudioClip, TimeInterval) -> TimeInterval
    let onSelectClip: (_ id: UUID, _ additive: Bool) -> Void
    let onEditGeneratedClip: (UUID) -> Void
    let onEmptyLaneClick: (TimeInterval) -> Void
    let onGhostChange: (ClipDragGhost?) -> Void
    let onBeginEdit: () -> Void
    let onEndEdit: () -> Void
    let onMoveClip: (_ clipID: UUID, _ toTrackID: UUID, _ timelineStart: TimeInterval) -> Void
    let onTrimStart: (_ clipID: UUID, _ newTimelineStart: TimeInterval) -> Void
    let onTrimEnd: (_ clipID: UUID, _ newTimelineEnd: TimeInterval) -> Void

    var body: some View {
        let hasGenerated = track.clips.contains(where: \.isGenerated)
        ZStack(alignment: .topLeading) {
            (hasGenerated ? SPTheme.trackLaneGenerated : SPTheme.trackLane)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            let t = max(0, Double(value.location.x) / pixelsPerSecond)
                            onEmptyLaneClick(t)
                        }
                )

            ForEach(track.clips) { clip in
                InteractiveClipView(
                    clip: clip,
                    peaks: peaksProvider(clip),
                    pixelsPerSecond: pixelsPerSecond,
                    trackIndex: trackIndex,
                    trackCount: allTracks.count,
                    isSelected: selectedClipIDs.contains(clip.id),
                    selectionCount: selectedClipIDs.count,
                    snapMoveStart: snapMoveStart,
                    snapTrimStart: snapTrimStart,
                    snapTrimEnd: snapTrimEnd,
                    onSelect: { additive in onSelectClip(clip.id, additive) },
                    onEditGenerated: { onEditGeneratedClip(clip.id) },
                    onGhostChange: onGhostChange,
                    onBeginEdit: onBeginEdit,
                    onEndEdit: onEndEdit,
                    onMoveClip: { clipID, trackDelta, timelineStart in
                        let destIndex = min(max(0, trackIndex + trackDelta), allTracks.count - 1)
                        onMoveClip(clipID, allTracks[destIndex].id, timelineStart)
                    },
                    onTrimStart: onTrimStart,
                    onTrimEnd: onTrimEnd
                )
                .offset(x: clip.timelineStart * pixelsPerSecond, y: 6)
            }

            Rectangle()
                .fill(SPTheme.playhead)
                .frame(width: 1, height: SPTheme.trackHeight)
                .offset(x: playheadTime * pixelsPerSecond)
                .allowsHitTesting(false)
        }
        .frame(width: contentWidth, height: SPTheme.trackHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SPTheme.border)
                .frame(height: 1)
        }
    }
}

private enum ClipDragKind {
    case move
    case trimStart
    case trimEnd
}

struct InteractiveClipView: View {
    let clip: AudioClip
    let peaks: [Float]
    let pixelsPerSecond: Double
    let trackIndex: Int
    let trackCount: Int
    let isSelected: Bool
    let selectionCount: Int
    let snapMoveStart: (AudioClip, TimeInterval) -> TimeInterval
    let snapTrimStart: (AudioClip, TimeInterval) -> TimeInterval
    let snapTrimEnd: (AudioClip, TimeInterval) -> TimeInterval
    let onSelect: (_ additive: Bool) -> Void
    let onEditGenerated: () -> Void
    let onGhostChange: (ClipDragGhost?) -> Void
    let onBeginEdit: () -> Void
    let onEndEdit: () -> Void
    let onMoveClip: (_ clipID: UUID, _ trackDelta: Int, _ timelineStart: TimeInterval) -> Void
    let onTrimStart: (_ clipID: UUID, _ newTimelineStart: TimeInterval) -> Void
    let onTrimEnd: (_ clipID: UUID, _ newTimelineEnd: TimeInterval) -> Void

    @State private var dragKind: ClipDragKind?
    @State private var dragOriginStart: TimeInterval = 0
    @State private var dragOriginEnd: TimeInterval = 0
    @State private var dragMaxExpandLeft: TimeInterval = 0
    @State private var dragMaxExpandRight: TimeInterval = 0
    @State private var trimPreviewStart: TimeInterval?
    @State private var trimPreviewDuration: TimeInterval?
    @State private var hoveringTrim = false
    @State private var trimLockedHaptic = false

    private let edgeHit: CGFloat = 10
    private let minClipDuration: TimeInterval = 0.02

    private var displayStart: TimeInterval { trimPreviewStart ?? clip.timelineStart }
    private var displayDuration: TimeInterval { trimPreviewDuration ?? clip.duration }

    private var modifierAdditive: Bool {
        let flags = NSEvent.modifierFlags
        return flags.contains(.control) || flags.contains(.command)
    }

    var body: some View {
        let height = SPTheme.trackHeight - 12
        let width = max(8, displayDuration * pixelsPerSecond)
        let trimDX = (displayStart - clip.timelineStart) * pixelsPerSecond
        let moving = dragKind == .move

        ZStack(alignment: .topLeading) {
            clipBody(width: width, height: height)
                .offset(x: trimDX)
                .opacity(moving ? 0.35 : 1)
        }
        .frame(width: max(8, clip.duration * pixelsPerSecond), height: height, alignment: .topLeading)
        .zIndex(moving || dragKind != nil ? 10 : (isSelected ? 2 : 0))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onSelect(false)
            if clip.isGenerated {
                onEditGenerated()
            }
        }
        .onTapGesture(count: 1) {
            onSelect(modifierAdditive)
        }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    if dragKind == nil {
                        // Keep multi-selection when dragging an already-selected clip.
                        if !isSelected {
                            onSelect(false)
                        }
                        onBeginEdit()
                        if value.startLocation.x <= edgeHit, selectionCount <= 1 {
                            dragKind = .trimStart
                        } else if value.startLocation.x >= max(8, clip.duration * pixelsPerSecond) - edgeHit,
                                  selectionCount <= 1 {
                            dragKind = .trimEnd
                        } else {
                            dragKind = .move
                        }
                        dragOriginStart = clip.timelineStart
                        dragOriginEnd = clip.timelineEnd
                        dragMaxExpandLeft = clip.maxExpandLeft
                        dragMaxExpandRight = clip.maxExpandRight
                        trimLockedHaptic = false
                    }

                    let dt = Double(value.translation.width) / pixelsPerSecond
                    switch dragKind {
                    case .trimStart:
                        let proposed = snapTrimStart(clip, dragOriginStart + dt)
                        let earliest = max(0, dragOriginStart - dragMaxExpandLeft)
                        let latest = dragOriginEnd - minClipDuration
                        let newStart = min(max(proposed, earliest), latest)
                        noteTrimLock(proposed: proposed, clamped: newStart)
                        trimPreviewStart = newStart
                        trimPreviewDuration = dragOriginEnd - newStart
                        onGhostChange(nil)
                    case .trimEnd:
                        let proposed = snapTrimEnd(clip, dragOriginEnd + dt)
                        let earliest = dragOriginStart + minClipDuration
                        let latest = dragOriginEnd + dragMaxExpandRight
                        let newEnd = min(max(proposed, earliest), latest)
                        noteTrimLock(proposed: proposed, clamped: newEnd)
                        trimPreviewStart = dragOriginStart
                        trimPreviewDuration = newEnd - dragOriginStart
                        onGhostChange(nil)
                    case .move:
                        let proposed = snapMoveStart(clip, max(0, dragOriginStart + dt))
                        let trackDelta = Int(round(Double(value.translation.height) / Double(SPTheme.trackHeight)))
                        let destTrack = min(max(0, trackIndex + trackDelta), trackCount - 1)
                        onGhostChange(
                            ClipDragGhost(
                                clipID: clip.id,
                                timelineStart: proposed,
                                duration: clip.duration,
                                trackIndex: destTrack
                            )
                        )
                    case .none:
                        break
                    }
                }
                .onEnded { value in
                    switch dragKind {
                    case .move:
                        let dt = Double(value.translation.width) / pixelsPerSecond
                        let proposed = snapMoveStart(clip, max(0, dragOriginStart + dt))
                        let trackDelta = Int(round(Double(value.translation.height) / Double(SPTheme.trackHeight)))
                        onMoveClip(clip.id, trackDelta, proposed)
                    case .trimStart:
                        if let start = trimPreviewStart {
                            onTrimStart(clip.id, start)
                        }
                    case .trimEnd:
                        if let start = trimPreviewStart, let dur = trimPreviewDuration {
                            onTrimEnd(clip.id, start + dur)
                        }
                    case .none:
                        break
                    }
                    trimPreviewStart = nil
                    trimPreviewDuration = nil
                    dragKind = nil
                    trimLockedHaptic = false
                    onGhostChange(nil)
                    onEndEdit()
                }
        )
    }

    private func noteTrimLock(proposed: TimeInterval, clamped: TimeInterval) {
        let locked = abs(proposed - clamped) > 0.000_5
        if locked, !trimLockedHaptic {
            trimLockedHaptic = true
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        } else if !locked {
            trimLockedHaptic = false
        }
    }

    @ViewBuilder
    private func clipBody(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(clipFillColor)

            WaveformShape(peaks: visiblePeaks(forWidth: width))
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                .padding(.horizontal, 2)
                .padding(.top, 16)
                .padding(.bottom, 4)

            Text(clipLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SPTheme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.top, 3)
                .allowsHitTesting(false)

            HStack {
                trimEdge(isLeading: true)
                Spacer(minLength: 0)
                trimEdge(isLeading: false)
            }
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(
                    isSelected ? SPTheme.accent : Color.white.opacity(hoveringTrim ? 0.55 : 0.25),
                    lineWidth: isSelected ? 2 : (hoveringTrim ? 1.5 : 1)
                )
        )
        .help(clip.isGenerated ? "Double-click to change tempo" : "")
    }

    private var clipFillColor: Color {
        switch clip.generation?.kind {
        case .introClicks: return SPTheme.clipFillClicks
        case .thump: return SPTheme.clipFillThump
        case .none: return SPTheme.clipFill
        }
    }

    private func trimEdge(isLeading: Bool) -> some View {
        Rectangle()
            .fill(hoveringTrim ? Color.white.opacity(0.55) : Color.white.opacity(0.25))
            .frame(width: 3)
            .padding(.vertical, 8)
            .frame(width: edgeHit, alignment: isLeading ? .leading : .trailing)
            .contentShape(Rectangle())
            .onHover { hovering in
                hoveringTrim = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var clipLabel: String {
        if let generation = clip.generation {
            let bpm = generation.tempoBPM
            let bpmText = abs(bpm - bpm.rounded()) < 0.05
                ? "\(Int(bpm.rounded()))"
                : String(format: "%.1f", bpm)
            return "\(generation.displayName) · \(bpmText) BPM"
        }
        let name = clip.sourceURL.deletingPathExtension().lastPathComponent
        let side: String
        switch clip.sourceChannel {
        case 0: side = "L"
        case 1: side = "R"
        default: side = "Ch\(clip.sourceChannel + 1)"
        }
        return "\(name) · \(side)"
    }

    private func visiblePeaks(forWidth width: CGFloat) -> [Float] {
        guard !peaks.isEmpty, clip.sourceDuration > 0 else { return [] }
        let start = displayStart
        let duration = displayDuration
        let sourceIn = clip.sourceIn + (start - clip.timelineStart)
        let startFrac = max(0, sourceIn / clip.sourceDuration)
        let endFrac = min(1, (sourceIn + duration) / clip.sourceDuration)
        let i0 = Int(startFrac * Double(peaks.count))
        let i1 = max(i0 + 1, Int(endFrac * Double(peaks.count)))
        let slice = Array(peaks[i0..<min(i1, peaks.count)])
        guard !slice.isEmpty else { return [] }

        let desired = max(8, Int(width / 2))
        if slice.count <= desired { return slice }
        var result = [Float](repeating: 0, count: desired)
        let step = Double(slice.count) / Double(desired)
        for i in 0..<desired {
            let s = Int(Double(i) * step)
            let e = min(slice.count, Int(Double(i + 1) * step))
            var maxVal: Float = 0
            for p in s..<max(s + 1, e) {
                maxVal = max(maxVal, slice[p])
            }
            result[i] = maxVal
        }
        return result
    }
}

struct WaveformShape: Shape {
    var peaks: [Float]

    func path(in rect: CGRect) -> Path {
        guard !peaks.isEmpty else { return Path() }
        var path = Path()
        let midY = rect.midY
        let count = peaks.count
        let step = rect.width / CGFloat(max(count, 1))
        for (i, peak) in peaks.enumerated() {
            let x = rect.minX + CGFloat(i) * step + step * 0.5
            let amp = CGFloat(min(1, peak)) * (rect.height * 0.5)
            path.move(to: CGPoint(x: x, y: midY - amp))
            path.addLine(to: CGPoint(x: x, y: midY + amp))
        }
        return path
    }
}
