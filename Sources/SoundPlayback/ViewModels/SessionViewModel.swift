import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var session: PlaybackSession {
        didSet { refreshDirtyFlag() }
    }
    @Published var documentURL: URL?
    @Published private(set) var isDirty = false
    @Published var statusMessage: String?
    @Published var outputDevices: [AudioOutputDevice] = []
    @Published var selectedDeviceUID: String?
    @Published var errorMessage: String?
    @Published var pixelsPerSecond: Double = 80
    @Published var isImporting = false
    @Published var pendingImport: PendingImport?
    @Published var showIntroClicksSheet = false
    @Published var showThumpTrackSheet = false
    @Published var showTapTempoSheet = false
    @Published var pendingGeneratedEdit: EditGeneratedClipRequest?
    @Published private(set) var detectedTempoBPM: Double?
    /// When true, playhead stays centered and the timeline scrolls with playback.
    @Published var activelyScroll = true
    /// When true, marker numbers always match left-to-right timeline order.
    @Published var marksAreSequential = true
    /// Snap clip edges to other clip edges while dragging / trimming.
    @Published var snapEnabled = true
    @Published var selectedClipIDs: Set<UUID> = []
    /// True while a track-name TextField owns the keyboard (blocks transport shortcuts).
    @Published var isEditingTrackName = false
    @Published var isEditingMarkerNote = false
    @Published var isEditingClipStart = false
    @Published var isEditingTimelineOrigin = false

    /// True while an inline text field owns the keyboard.
    var isEditingInlineText: Bool {
        isEditingTrackName || isEditingMarkerNote || isEditingClipStart || isEditingTimelineOrigin
    }
    /// Bumped when the timeline should consider scrolling to show the playhead (stop / marker jump).
    @Published private(set) var playheadFocusToken = UUID()
    @Published private(set) var canUndo = false
    /// Waveform peaks keyed by "url.absoluteString#channel".
    @Published private(set) var waveformPeaks: [String: [Float]] = [:]

    let engine = PlaybackEngine()
    private(set) var audioBuffers: [URL: ImportedAudio] = [:]
    private var importQueue: [PendingImport] = []

    /// Pre-solo mute states; non-nil while exclusive solo is engaged.
    private var muteSnapshot: [UUID: Bool]?
    private var clipUndoStack: [[Track]] = []
    private var undoGestureOpen = false
    /// Copied clips with the track they came from (paste stays on those tracks).
    private var clipClipboard: [(trackIndex: Int, clip: AudioClip)] = []
    private var cleanSession: PlaybackSession
    private var suppressDirtyTracking = false
    private var statusClearTask: Task<Void, Never>?

    static let minPixelsPerSecond: Double = 12
    static let maxPixelsPerSecond: Double = 400
    private static let minClipDuration: TimeInterval = 0.02
    /// One arrow-key step (half a second).
    private static let playheadFrameDuration: TimeInterval = 0.5
    private static let maxUndoSteps = 10
    /// Snap distance in pixels (converted via pixelsPerSecond).
    private static let snapPixels: Double = 12


    var selectedDevice: AudioOutputDevice? {
        guard let selectedDeviceUID else { return nil }
        return outputDevices.first { $0.uid == selectedDeviceUID }
    }

    var availableOutputCount: Int {
        selectedDevice?.usableOutputSlots ?? 2
    }

    var documentDisplayName: String {
        if let url = documentURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return "UNTITLED"
    }

    init(session: PlaybackSession = .blank()) {
        self.session = session
        self.cleanSession = session
        refreshDevices()
        if let uid = self.session.outputDeviceUID,
           outputDevices.contains(where: { $0.uid == uid }) {
            selectedDeviceUID = uid
        } else {
            selectedDeviceUID = outputDevices.first?.uid
        }
        self.session.outputDeviceUID = selectedDeviceUID
        engine.setPlayStart(self.session.playStartTime)
        reconfigureEngine()
        markClean()
    }

    func refreshDevices() {
        outputDevices = AudioDeviceService.outputDevices()
        if let selectedDeviceUID,
           !outputDevices.contains(where: { $0.uid == selectedDeviceUID }) {
            self.selectedDeviceUID = outputDevices.first?.uid
            session.outputDeviceUID = self.selectedDeviceUID
            reconfigureEngine()
        }
    }

    func selectDevice(_ uid: String?) {
        selectedDeviceUID = uid
        session.outputDeviceUID = uid
        reconfigureEngine()
    }

    func zoomBy(factor: Double, baseline: Double) {
        pixelsPerSecond = min(
            Self.maxPixelsPerSecond,
            max(Self.minPixelsPerSecond, baseline * factor)
        )
    }

    func peaks(for clip: AudioClip) -> [Float] {
        waveformPeaks[peakKey(url: clip.sourceURL, channel: clip.sourceChannel)] ?? []
    }

    func requestPlayheadFocus() {
        playheadFocusToken = UUID()
    }

    func setMarksAreSequential(_ enabled: Bool) {
        marksAreSequential = enabled
        if enabled {
            renumberMarkersByTimeline()
        }
    }

    // MARK: - Tracks

    func addTrack() {
        let index = session.tracks.count + 1
        session.tracks.append(Track(name: "Track \(index)"))
        syncMix()
    }

    func deleteTrack(id: UUID) {
        guard let idx = session.tracks.firstIndex(where: { $0.id == id }) else { return }
        guard session.tracks.count > 1 else {
            errorMessage = "At least one track is required."
            return
        }

        pushClipUndo()

        let removed = session.tracks[idx]
        let removedClipIDs = Set(removed.clips.map(\.id))
        let removedPairIDs = Set(removed.clips.compactMap(\.pairID))

        session.tracks.remove(at: idx)

        // Orphaned stereo partners become normal mono clips.
        if !removedPairIDs.isEmpty {
            for t in session.tracks.indices {
                for c in session.tracks[t].clips.indices {
                    if let pairID = session.tracks[t].clips[c].pairID,
                       removedPairIDs.contains(pairID) {
                        session.tracks[t].clips[c].pairID = nil
                    }
                }
            }
        }

        selectedClipIDs.subtract(removedClipIDs)
        muteSnapshot?[id] = nil
        if muteSnapshot?.isEmpty == true { muteSnapshot = nil }

        // Remap clipboard track indices after the hole closes.
        clipClipboard = clipClipboard.compactMap { item in
            if item.trackIndex == idx { return nil }
            let newIndex = item.trackIndex > idx ? item.trackIndex - 1 : item.trackIndex
            return (newIndex, item.clip)
        }

        restackDefaultTrackNames()
        syncMix()
        showStatus("Track deleted")
    }

    /// Rename sequential "Track N" headers after delete so numbering stays tight.
    private func restackDefaultTrackNames() {
        var next = 1
        for i in session.tracks.indices {
            if session.tracks[i].name.range(of: #"^Track \d+$"#, options: .regularExpression) != nil {
                session.tracks[i].name = "Track \(next)"
                next += 1
            }
        }
    }

    func toggleOutput(trackID: UUID, channel: Int) {
        guard (1...4).contains(channel), channel <= availableOutputCount else { return }
        guard let idx = session.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        session.tracks[idx].outputMask.formSymmetricDifference(.channel(channel))
        syncMix()
    }

    func setVolume(trackID: UUID, volume: Double) {
        guard let idx = session.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        session.tracks[idx].volume = min(1, max(0, volume))
        syncMix()
    }

    func renameTrack(id: UUID, name: String) {
        guard let idx = session.tracks.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.tracks[idx].name = trimmed
    }

    func setSolo(trackID: UUID, enabled: Bool) {
        guard session.tracks.contains(where: { $0.id == trackID }) else { return }

        if enabled {
            if muteSnapshot == nil {
                muteSnapshot = Dictionary(uniqueKeysWithValues: session.tracks.map { ($0.id, $0.isMuted) })
            }
            for i in session.tracks.indices {
                let isTarget = session.tracks[i].id == trackID
                session.tracks[i].isSoloed = isTarget
                session.tracks[i].isMuted = !isTarget
            }
        } else {
            guard session.tracks.first(where: { $0.id == trackID })?.isSoloed == true else { return }
            if let snapshot = muteSnapshot {
                for i in session.tracks.indices {
                    session.tracks[i].isSoloed = false
                    session.tracks[i].isMuted = snapshot[session.tracks[i].id] ?? false
                }
            } else {
                for i in session.tracks.indices {
                    session.tracks[i].isSoloed = false
                }
            }
            muteSnapshot = nil
        }
        syncMix()
    }

    func setMute(trackID: UUID, muted: Bool) {
        guard let idx = session.tracks.firstIndex(where: { $0.id == trackID }) else { return }

        if muteSnapshot != nil, !muted {
            let soloID = session.tracks.first(where: \.isSoloed)?.id
            if let soloID, soloID != trackID {
                for i in session.tracks.indices {
                    session.tracks[i].isSoloed = false
                }
                if let soloIdx = session.tracks.firstIndex(where: { $0.id == soloID }) {
                    session.tracks[soloIdx].isMuted = false
                }
                session.tracks[idx].isMuted = false
                muteSnapshot = nil
                syncMix()
                return
            }
        }

        session.tracks[idx].isMuted = muted
        syncMix()
    }

    // MARK: - Clip edits + undo

    /// Call once at the start of a move/trim gesture.
    func beginClipEdit() {
        guard !undoGestureOpen else { return }
        pushClipUndo()
        undoGestureOpen = true
    }

    func endClipEdit() {
        undoGestureOpen = false
    }

    func undoClipEdit() {
        guard let previous = clipUndoStack.popLast() else { return }
        undoGestureOpen = false
        session.tracks = previous
        canUndo = !clipUndoStack.isEmpty
        syncMix()
    }

    private func pushClipUndo() {
        clipUndoStack.append(session.tracks)
        if clipUndoStack.count > Self.maxUndoSteps {
            clipUndoStack.removeFirst()
        }
        canUndo = true
    }

    func moveClip(clipID: UUID, toTrackID: UUID, timelineStart: TimeInterval) {
        // Group-move when the dragged clip is part of a multi-selection.
        if selectedClipIDs.contains(clipID), selectedClipIDs.count > 1 {
            moveSelectedClips(draggedClipID: clipID, toTrackID: toTrackID, timelineStart: timelineStart)
            return
        }
        moveSingleClip(clipID: clipID, toTrackID: toTrackID, timelineStart: timelineStart, movePairedSibling: true)
        syncMix()
    }

    /// Set a clip's timeline start from typed input (`12.5`, `01:23.45`, or `0:01:23.45`).
    /// Values are display times (include timeline origin).
    /// When `moveMarkers` is true, markers that sit on this clip move by the same delta.
    func setClipStartTime(clipID: UUID, raw: String, moveMarkers: Bool) {
        guard let display = TimeFormat.parse(raw) else {
            errorMessage = "Enter a start time like 12.5, 01:23.45, or 0:01:23.45"
            return
        }
        let start = max(0, display - session.timelineOrigin)
        guard let loc = locateClip(clipID) else { return }
        let clip = session.tracks[loc.track].clips[loc.clip]
        let oldStart = clip.timelineStart
        let oldEnd = clip.timelineEnd
        let dt = start - oldStart
        guard abs(dt) > 1e-9 else { return }

        let trackID = session.tracks[loc.track].id
        beginClipEdit()
        moveClip(clipID: clipID, toTrackID: trackID, timelineStart: start)

        if moveMarkers {
            for i in session.markers.indices {
                let t = session.markers[i].time
                if t >= oldStart - 1e-6, t <= oldEnd + 1e-6 {
                    session.markers[i].time = max(0, t + dt)
                }
            }
            session.markers.sort()
            if marksAreSequential {
                renumberMarkersByTimeline()
            }
        }

        endClipEdit()
        let markerNote = moveMarkers ? " · markers moved" : ""
        showStatus("Clip start → \(TimeFormat.clock(display))\(markerNote)")
    }

    /// Set the ruler / clock display origin (timeline left-edge label).
    /// Clips stay put. Markers are re-anchored to their clips so they stay lined up with audio
    /// (same absolute times as before when clips did not move).
    func setTimelineOrigin(raw: String) {
        guard let origin = TimeFormat.parse(raw) else {
            errorMessage = "Enter a timeline start like 0:00:00.00 or 1:00:00"
            return
        }
        let newOrigin = max(0, origin)
        let oldOrigin = session.timelineOrigin
        guard abs(newOrigin - oldOrigin) > 1e-9 else { return }

        // Remember each marker’s offset from the clip it sits on (or nearest clip start).
        let anchors = markerAnchorsToClips()

        session.timelineOrigin = newOrigin

        // Re-apply anchors so marks stay with audio, not with the old ruler labels.
        applyMarkerAnchors(anchors)

        if marksAreSequential {
            renumberMarkersByTimeline()
        }
        showStatus("Timeline start → \(TimeFormat.clockWithHours(session.timelineOrigin))")
    }

    /// Offset of each marker from a clip it belongs to (containing clip, else nearest start).
    private func markerAnchorsToClips() -> [(markerID: UUID, clipID: UUID, offset: TimeInterval)] {
        let clips = session.tracks.flatMap(\.clips)
        guard !clips.isEmpty else { return [] }

        var result: [(markerID: UUID, clipID: UUID, offset: TimeInterval)] = []
        for marker in session.markers {
            let containing = clips.first { clip in
                marker.time >= clip.timelineStart - 1e-6 && marker.time <= clip.timelineEnd + 1e-6
            }
            let clip = containing ?? clips.min(by: {
                abs($0.timelineStart - marker.time) < abs($1.timelineStart - marker.time)
            })
            guard let clip else { continue }
            result.append((marker.id, clip.id, marker.time - clip.timelineStart))
        }
        return result
    }

    private func applyMarkerAnchors(_ anchors: [(markerID: UUID, clipID: UUID, offset: TimeInterval)]) {
        for anchor in anchors {
            guard let clip = session.tracks.flatMap(\.clips).first(where: { $0.id == anchor.clipID }),
                  let idx = session.markers.firstIndex(where: { $0.id == anchor.markerID })
            else { continue }
            session.markers[idx].time = max(0, clip.timelineStart + anchor.offset)
        }
        session.markers.sort()
    }

    /// Move every selected clip by the same time/track delta as the dragged clip.
    private func moveSelectedClips(draggedClipID: UUID, toTrackID: UUID, timelineStart: TimeInterval) {
        guard let dragLoc = locateClip(draggedClipID),
              let destTrack = session.tracks.firstIndex(where: { $0.id == toTrackID })
        else { return }

        let oldStart = session.tracks[dragLoc.track].clips[dragLoc.clip].timelineStart
        let dt = timelineStart - oldStart
        let trackDelta = destTrack - dragLoc.track

        // Snapshot before mutating indices.
        var payloads: [(track: Int, clip: AudioClip)] = []
        for id in selectedClipIDs {
            guard let loc = locateClip(id) else { continue }
            payloads.append((loc.track, session.tracks[loc.track].clips[loc.clip]))
        }
        guard !payloads.isEmpty else { return }

        let ids = Set(payloads.map(\.clip.id))
        for id in ids {
            guard let loc = locateClip(id) else { continue }
            session.tracks[loc.track].clips.remove(at: loc.clip)
        }

        var newSelection: Set<UUID> = []
        let maxNeeded = payloads.map { $0.track + trackDelta }.max() ?? 0
        ensureTrackCount(max(maxNeeded + 1, session.tracks.count))
        for payload in payloads {
            var clip = payload.clip
            clip.timelineStart = max(0, clip.timelineStart + dt)
            let dest = min(max(0, payload.track + trackDelta), session.tracks.count - 1)
            session.tracks[dest].clips.append(clip)
            newSelection.insert(clip.id)
        }
        selectedClipIDs = newSelection
        syncMix()
    }

    private func moveSingleClip(
        clipID: UUID,
        toTrackID: UUID,
        timelineStart: TimeInterval,
        movePairedSibling: Bool
    ) {
        guard let fromTrack = trackIndex(containingClip: clipID),
              let toTrack = session.tracks.firstIndex(where: { $0.id == toTrackID }),
              let clipIndex = session.tracks[fromTrack].clips.firstIndex(where: { $0.id == clipID })
        else { return }

        var clip = session.tracks[fromTrack].clips[clipIndex]
        let snappedStart = snapEnabled
            ? snappedTimelineStart(for: clip, proposedStart: timelineStart)
            : max(0, timelineStart)
        let pairID = clip.pairID
        let trackDelta = toTrack - fromTrack

        clip.timelineStart = snappedStart
        if fromTrack == toTrack {
            session.tracks[fromTrack].clips[clipIndex] = clip
        } else {
            session.tracks[fromTrack].clips.remove(at: clipIndex)
            ensureTrackCount(toTrack + 1)
            session.tracks[toTrack].clips.append(clip)
        }

        if movePairedSibling,
           let pairID,
           let sibling = locatePairedClip(pairID: pairID, excludingClipID: clipID) {
            var sib = session.tracks[sibling.track].clips[sibling.clip]
            sib.timelineStart = snappedStart
            let siblingDest = sibling.track + trackDelta
            ensureTrackCount(max(siblingDest, toTrack) + 1)
            if sibling.track == siblingDest {
                session.tracks[sibling.track].clips[sibling.clip] = sib
            } else {
                session.tracks[sibling.track].clips.remove(at: sibling.clip)
                session.tracks[siblingDest].clips.append(sib)
            }
        }
    }

    func trimClipStart(clipID: UUID, newTimelineStart: TimeInterval) {
        guard let loc = locateClip(clipID) else { return }
        applyTrimStart(at: loc, newTimelineStart: newTimelineStart)

        if let pairID = session.tracks[loc.track].clips[loc.clip].pairID,
           let sibling = locatePairedClip(pairID: pairID, excludingClipID: clipID) {
            // Keep partner locked: same timeline window / source in / duration.
            let primary = session.tracks[loc.track].clips[loc.clip]
            session.tracks[sibling.track].clips[sibling.clip].timelineStart = primary.timelineStart
            session.tracks[sibling.track].clips[sibling.clip].sourceIn = primary.sourceIn
            session.tracks[sibling.track].clips[sibling.clip].duration = primary.duration
        }
        syncMix()
    }

    func trimClipEnd(clipID: UUID, newTimelineEnd: TimeInterval) {
        guard let loc = locateClip(clipID) else { return }
        applyTrimEnd(at: loc, newTimelineEnd: newTimelineEnd)

        if let pairID = session.tracks[loc.track].clips[loc.clip].pairID,
           let sibling = locatePairedClip(pairID: pairID, excludingClipID: clipID) {
            let primary = session.tracks[loc.track].clips[loc.clip]
            session.tracks[sibling.track].clips[sibling.clip].duration = primary.duration
            session.tracks[sibling.track].clips[sibling.clip].timelineStart = primary.timelineStart
            session.tracks[sibling.track].clips[sibling.clip].sourceIn = primary.sourceIn
        }
        syncMix()
    }

    private func applyTrimStart(at loc: (track: Int, clip: Int), newTimelineStart: TimeInterval) {
        var clip = session.tracks[loc.track].clips[loc.clip]
        var proposedStart = max(0, newTimelineStart)
        if snapEnabled {
            proposedStart = snap(proposedStart, excludingClipID: clip.id, alsoExcludePairOf: clip.pairID)
        }
        var delta = proposedStart - clip.timelineStart
        if delta < 0 {
            delta = max(delta, -clip.maxExpandLeft)
        } else {
            delta = min(delta, max(0, clip.duration - Self.minClipDuration))
        }
        clip.timelineStart += delta
        clip.sourceIn += delta
        clip.duration -= delta
        session.tracks[loc.track].clips[loc.clip] = clip
    }

    private func applyTrimEnd(at loc: (track: Int, clip: Int), newTimelineEnd: TimeInterval) {
        var clip = session.tracks[loc.track].clips[loc.clip]
        var proposedEnd = newTimelineEnd
        if snapEnabled {
            proposedEnd = snap(proposedEnd, excludingClipID: clip.id, alsoExcludePairOf: clip.pairID)
        }
        var newDuration = proposedEnd - clip.timelineStart
        newDuration = max(Self.minClipDuration, newDuration)
        newDuration = min(newDuration, clip.sourceDuration - clip.sourceIn)
        clip.duration = newDuration
        session.tracks[loc.track].clips[loc.clip] = clip
    }

    /// Live preview helper for drag UI (same snap rules as commit).
    func snappedMoveStart(for clip: AudioClip, proposedStart: TimeInterval) -> TimeInterval {
        guard snapEnabled else { return max(0, proposedStart) }
        return snappedTimelineStart(for: clip, proposedStart: proposedStart)
    }

    func snappedTrimStart(for clip: AudioClip, proposedStart: TimeInterval) -> TimeInterval {
        guard snapEnabled else { return max(0, proposedStart) }
        return snap(max(0, proposedStart), excludingClipID: clip.id, alsoExcludePairOf: clip.pairID)
    }

    func snappedTrimEnd(for clip: AudioClip, proposedEnd: TimeInterval) -> TimeInterval {
        guard snapEnabled else { return proposedEnd }
        return snap(proposedEnd, excludingClipID: clip.id, alsoExcludePairOf: clip.pairID)
    }

    private func snappedTimelineStart(for clip: AudioClip, proposedStart: TimeInterval) -> TimeInterval {
        let start = max(0, proposedStart)
        let end = start + clip.duration
        let points = edgePoints(excludingClipID: clip.id, alsoExcludePairOf: clip.pairID)
        let threshold = snapThresholdSeconds()

        var bestStart = start
        var bestDist = threshold

        for p in points {
            let dStart = abs(start - p)
            if dStart < bestDist {
                bestDist = dStart
                bestStart = p
            }
            let dEnd = abs(end - p)
            if dEnd < bestDist {
                bestDist = dEnd
                bestStart = p - clip.duration
            }
        }
        return max(0, bestStart)
    }

    private func snap(
        _ time: TimeInterval,
        excludingClipID: UUID,
        alsoExcludePairOf pairID: UUID? = nil
    ) -> TimeInterval {
        let points = edgePoints(excludingClipID: excludingClipID, alsoExcludePairOf: pairID)
        let threshold = snapThresholdSeconds()
        var best = time
        var bestDist = threshold
        for p in points {
            let d = abs(time - p)
            if d < bestDist {
                bestDist = d
                best = p
            }
        }
        return best
    }

    private func edgePoints(excludingClipID: UUID, alsoExcludePairOf pairID: UUID? = nil) -> [TimeInterval] {
        var points: [TimeInterval] = []
        for track in session.tracks {
            for clip in track.clips {
                if clip.id == excludingClipID { continue }
                if let pairID, clip.pairID == pairID { continue }
                points.append(clip.timelineStart)
                points.append(clip.timelineEnd)
            }
        }
        for marker in session.markers {
            points.append(marker.time)
        }
        return points
    }

    private func snapThresholdSeconds() -> TimeInterval {
        Self.snapPixels / max(pixelsPerSecond, 1)
    }

    private func trackIndex(containingClip clipID: UUID) -> Int? {
        session.tracks.firstIndex { $0.clips.contains { $0.id == clipID } }
    }

    private func locateClip(_ clipID: UUID) -> (track: Int, clip: Int)? {
        for t in session.tracks.indices {
            if let c = session.tracks[t].clips.firstIndex(where: { $0.id == clipID }) {
                return (t, c)
            }
        }
        return nil
    }

    private func locatePairedClip(pairID: UUID, excludingClipID: UUID) -> (track: Int, clip: Int)? {
        for t in session.tracks.indices {
            if let c = session.tracks[t].clips.firstIndex(where: { $0.pairID == pairID && $0.id != excludingClipID }) {
                return (t, c)
            }
        }
        return nil
    }

    func trackHasAudio(at index: Int) -> Bool {
        guard session.tracks.indices.contains(index) else { return false }
        return !session.tracks[index].clips.isEmpty
    }

    func selectClip(id: UUID, additive: Bool = false) {
        let ids = selectionIDs(for: id)
        if additive {
            if ids.isSubset(of: selectedClipIDs) {
                selectedClipIDs.subtract(ids)
            } else {
                selectedClipIDs.formUnion(ids)
            }
        } else {
            selectedClipIDs = ids
        }
    }

    func clearClipSelection() {
        selectedClipIDs = []
    }

    func setDetectedTempoBPM(_ bpm: Double) {
        detectedTempoBPM = max(20, min(400, (bpm * 10).rounded() / 10))
        showStatus("Tempo \(Self.formatTempo(detectedTempoBPM!)) BPM")
    }

    func deleteSelectedClips() {
        guard !selectedClipIDs.isEmpty else { return }
        beginClipEdit()
        let ids = selectedClipIDs
        for t in session.tracks.indices {
            session.tracks[t].clips.removeAll { ids.contains($0.id) }
        }
        selectedClipIDs = []
        endClipEdit()
        syncMix()
    }

    func copySelectedClips() {
        var items: [(trackIndex: Int, clip: AudioClip)] = []
        for id in selectedClipIDs {
            guard let loc = locateClip(id) else { continue }
            items.append((loc.track, session.tracks[loc.track].clips[loc.clip]))
        }
        items.sort { $0.trackIndex < $1.trackIndex }
        clipClipboard = items
        if !items.isEmpty {
            showStatus(items.count == 1 ? "Copied clip" : "Copied \(items.count) clips")
        }
    }

    func pasteClipsAtPlayhead() {
        guard !clipClipboard.isEmpty else { return }
        pushClipUndo()

        let start = placementPlayMarkerTime()
        let pastingPair = clipClipboard.count > 1
            && clipClipboard.allSatisfy { $0.clip.pairID != nil }
        let newPairID = pastingPair ? UUID() : nil
        var newSelection: Set<UUID> = []

        for item in clipClipboard {
            guard session.tracks.indices.contains(item.trackIndex) else { continue }
            var copy = item.clip
            copy.id = UUID()
            copy.timelineStart = start
            copy.pairID = newPairID
            session.tracks[item.trackIndex].clips.append(copy)
            newSelection.insert(copy.id)
        }

        guard !newSelection.isEmpty else { return }
        selectedClipIDs = newSelection
        syncMix()
        showStatus("Pasted at playhead")
    }

    private func selectionIDs(for clipID: UUID) -> Set<UUID> {
        guard let loc = locateClip(clipID) else { return [clipID] }
        let clip = session.tracks[loc.track].clips[loc.clip]
        var ids: Set<UUID> = [clip.id]
        if let pairID = clip.pairID,
           let sibling = locatePairedClip(pairID: pairID, excludingClipID: clip.id) {
            ids.insert(session.tracks[sibling.track].clips[sibling.clip].id)
        }
        return ids
    }

    // MARK: - Transport / markers

    func setPlayStart(at time: TimeInterval) {
        let t = max(0, time)
        session.playStartTime = t
        engine.setPlayStart(t)
    }

    /// Nudge playhead by clock "frames" (centiseconds — matches `MM:SS.ff`).
    func nudgePlayheadByFrames(_ frames: Int) {
        let step = Self.playheadFrameDuration
        let current = engine.transport == .stopped ? session.playStartTime : engine.playheadTime
        let t = max(0, current + Double(frames) * step)
        session.playStartTime = t
        engine.seekPlayhead(to: t, alsoSetPlayStart: true)
        requestPlayheadFocus()
    }

    func play() {
        syncMix()
        engine.play()
    }

    func pause() {
        engine.pause()
    }

    func stop() {
        engine.stop()
        requestPlayheadFocus()
    }

    func togglePlayStop() {
        if engine.transport == .playing {
            stop()
        } else {
            play()
        }
    }

    func addMarkerAtPlayhead() {
        let time = engine.transport == .stopped ? session.playStartTime : engine.playheadTime
        if marksAreSequential {
            session.markers.append(TimelineMarker(number: 0, time: time))
            renumberMarkersByTimeline()
        } else {
            let nextNumber = (session.markers.map(\.number).max() ?? 0) + 1
            session.markers.append(TimelineMarker(number: nextNumber, time: time))
            session.markers.sort()
        }
    }

    func moveMarker(id: UUID, to time: TimeInterval) {
        guard let idx = session.markers.firstIndex(where: { $0.id == id }) else { return }
        session.markers[idx].time = max(0, time)
        if marksAreSequential {
            renumberMarkersByTimeline()
        } else {
            session.markers.sort()
        }
    }

    func deleteMarker(id: UUID) {
        session.markers.removeAll { $0.id == id }
        if marksAreSequential {
            renumberMarkersByTimeline()
        }
    }

    func setMarkerNote(id: UUID, note: String) {
        guard let idx = session.markers.firstIndex(where: { $0.id == id }) else { return }
        session.markers[idx].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func jumpToMarker(number: Int) {
        guard let marker = session.markers.first(where: { $0.number == number }) else { return }
        let t = marker.time
        session.playStartTime = t
        // Atomic seek — updates play-start + playhead and bumps seek generation so audio can't clobber it.
        engine.seekPlayhead(to: t, alsoSetPlayStart: true)
        // Always bring the playhead into view (including mid-playback jumps).
        requestPlayheadFocus()
    }

    func handleDigitKey(_ digit: Int, shift: Bool) {
        guard let number = TimelineMarker.numberForKey(digit: digit, shift: shift) else { return }
        jumpToMarker(number: number)
    }

    private func renumberMarkersByTimeline() {
        session.markers.sort { $0.time < $1.time }
        for i in session.markers.indices {
            session.markers[i].number = i + 1
        }
    }

    // MARK: - Import

    func importAudio(urls: [URL]) {
        Task {
            var pending: [PendingImport] = []
            for url in urls {
                _ = url.startAccessingSecurityScopedResource()
                do {
                    let channels = try AudioFileImporter.channelCount(at: url)
                    pending.append(PendingImport(url: url, sourceChannelCount: channels))
                } catch {
                    errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
            guard !pending.isEmpty else { return }
            importQueue.append(contentsOf: pending)
            presentNextImportIfNeeded()
        }
    }

    func cancelPendingImport() {
        guard let current = pendingImport else { return }
        importQueue.removeAll { $0.id == current.id }
        pendingImport = nil
        presentNextImportIfNeeded()
    }

    func confirmPendingImport(_ choice: ImportPlacementChoice) {
        guard let current = pendingImport else { return }
        pendingImport = nil
        importQueue.removeAll { $0.id == current.id }
        isImporting = true
        Task {
            defer {
                isImporting = false
                presentNextImportIfNeeded()
            }
            do {
                let imported = try AudioFileImporter.importFile(
                    at: current.url,
                    targetSampleRate: session.sampleRate
                )
                audioBuffers[current.url] = imported
                for channel in 0..<min(current.placementChannels, imported.channelCount) {
                    waveformPeaks[peakKey(url: current.url, channel: channel)] = imported.peaks[channel]
                }
                placeImported(imported, placementChannels: current.placementChannels, choice: choice)
                syncMix()
            } catch {
                errorMessage = "\(current.displayName): \(error.localizedDescription)"
            }
        }
    }

    private func presentNextImportIfNeeded() {
        guard pendingImport == nil else { return }
        pendingImport = importQueue.first
    }

    // MARK: - Generated audio

    func addIntroClicks(_ request: IntroClicksRequest) {
        do {
            let imported = try GeneratedAudioService.makeIntroClicks(
                tempoBPM: request.tempoBPM,
                clickCount: request.clickCount,
                sampleRate: session.sampleRate
            )
            let generation = ClipGeneration.introClicks(
                tempoBPM: request.tempoBPM,
                clickCount: request.clickCount
            )
            placeGenerated(
                imported,
                on: request.track,
                generation: generation,
                preferredTrackName: "Clicks"
            )
            showStatus("Intro clicks added")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addThumpTrack(_ request: ThumpTrackRequest) {
        do {
            let imported = try GeneratedAudioService.makeThumpTrack(
                tempoBPM: request.tempoBPM,
                frequencyHz: request.frequencyHz,
                thumpTenths: request.thumpTenths,
                trackLengthSeconds: request.trackLengthSeconds,
                sampleRate: session.sampleRate
            )
            let generation = ClipGeneration.thump(
                tempoBPM: request.tempoBPM,
                frequencyHz: request.frequencyHz,
                thumpTenths: request.thumpTenths,
                trackLengthSeconds: request.trackLengthSeconds
            )
            placeGenerated(
                imported,
                on: request.track,
                generation: generation,
                preferredTrackName: "Thump"
            )
            showStatus("Thump track added")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginEditGeneratedClip(clipID: UUID) {
        guard let loc = locateClip(clipID),
              let generation = session.tracks[loc.track].clips[loc.clip].generation else { return }
        let clip = session.tracks[loc.track].clips[loc.clip]
        pendingGeneratedEdit = EditGeneratedClipRequest(
            id: clipID,
            kind: generation.kind,
            title: generation.displayName,
            tempoBPM: generation.tempoBPM,
            clickCount: generation.clickCount ?? 4,
            frequencyHz: generation.frequencyHz ?? 55,
            thumpTenths: generation.thumpTenths ?? 2,
            trackLengthSeconds: generation.trackLengthSeconds ?? max(clip.duration, 4)
        )
    }

    func applyGeneratedEdit(_ request: EditGeneratedClipRequest) {
        pendingGeneratedEdit = nil
        guard let loc = locateClip(request.id) else { return }
        var clip = session.tracks[loc.track].clips[loc.clip]
        guard var generation = clip.generation else { return }

        let bpm = max(20, min(400, request.tempoBPM))
        generation.tempoBPM = bpm

        do {
            let imported: ImportedAudio
            switch generation.kind {
            case .introClicks:
                let count = max(1, min(32, request.clickCount))
                imported = try GeneratedAudioService.makeIntroClicks(
                    tempoBPM: bpm,
                    clickCount: count,
                    sampleRate: session.sampleRate
                )
                generation.clickCount = count
            case .thump:
                let freq = max(20, min(4000, request.frequencyHz))
                let tenths = max(1, min(20, request.thumpTenths))
                let length = max(0.5, min(600, request.trackLengthSeconds))
                imported = try GeneratedAudioService.makeThumpTrack(
                    tempoBPM: bpm,
                    frequencyHz: freq,
                    thumpTenths: tenths,
                    trackLengthSeconds: length,
                    sampleRate: session.sampleRate
                )
                generation.frequencyHz = freq
                generation.thumpTenths = tenths
                generation.trackLengthSeconds = length
            }

            let oldURL = clip.sourceURL
            audioBuffers[imported.url] = imported
            if let peaks = imported.peaks.first {
                waveformPeaks[peakKey(url: imported.url, channel: 0)] = peaks
            }

            clip.sourceURL = imported.url
            clip.sourceIn = 0
            clip.duration = imported.duration
            clip.sourceDuration = imported.duration
            clip.generation = generation
            session.tracks[loc.track].clips[loc.clip] = clip

            if oldURL != imported.url {
                audioBuffers.removeValue(forKey: oldURL)
                waveformPeaks.removeValue(forKey: peakKey(url: oldURL, channel: 0))
            }

            syncMix()
            showStatus("\(generation.displayName) updated")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func formatTempo(_ bpm: Double) -> String {
        if abs(bpm - bpm.rounded()) < 0.05 {
            return "\(Int(bpm.rounded()))"
        }
        return String(format: "%.1f", bpm)
    }

    private func placeGenerated(
        _ imported: ImportedAudio,
        on trackChoice: GeneratedPlacementTrack,
        generation: ClipGeneration,
        preferredTrackName: String
    ) {
        audioBuffers[imported.url] = imported
        if let peaks = imported.peaks.first {
            waveformPeaks[peakKey(url: imported.url, channel: 0)] = peaks
        }

        let trackIndex: Int
        switch trackChoice {
        case .existing(let index):
            trackIndex = index
            ensureTrackCount(trackIndex + 1)
        case .newTrack:
            addTrack()
            trackIndex = session.tracks.count - 1
            session.tracks[trackIndex].name = preferredTrackName
        }

        let start = placementPlayMarkerTime()
        if session.tracks[trackIndex].clips.isEmpty {
            session.tracks[trackIndex].outputMask = .out1
            // Rename empty destination tracks that still have the default name.
            if session.tracks[trackIndex].name.hasPrefix("Track ") {
                session.tracks[trackIndex].name = preferredTrackName
            }
        }
        session.tracks[trackIndex].clips.append(
            AudioClip(
                sourceURL: imported.url,
                sourceChannel: 0,
                timelineStart: start,
                sourceIn: 0,
                duration: imported.duration,
                sourceDuration: imported.duration,
                pairID: nil,
                generation: generation
            )
        )
        syncMix()
    }

    private func placementPlayMarkerTime() -> TimeInterval {
        engine.transport == .stopped ? session.playStartTime : engine.playheadTime
    }

    private func placeImported(
        _ imported: ImportedAudio,
        placementChannels: Int,
        choice: ImportPlacementChoice
    ) {
        let fileName = imported.url.deletingPathExtension().lastPathComponent

        switch choice.mode {
        case .mono(let trackIndex):
            ensureTrackCount(trackIndex + 1)
            let wasEmpty = session.tracks[trackIndex].clips.isEmpty
            if choice.resolution == .replace {
                session.tracks[trackIndex].clips.removeAll()
            }
            let start = choice.resolution == .append
                ? appendStart(forTrackIndices: [trackIndex])
                : session.playStartTime
            if session.tracks[trackIndex].clips.isEmpty {
                session.tracks[trackIndex].outputMask = .out1
            }
            session.tracks[trackIndex].clips.append(
                AudioClip(
                    sourceURL: imported.url,
                    sourceChannel: 0,
                    timelineStart: start,
                    sourceIn: 0,
                    duration: imported.duration,
                    sourceDuration: imported.duration,
                    pairID: nil
                )
            )
            if choice.resolution == .replace || wasEmpty || isDefaultTrackName(session.tracks[trackIndex].name) {
                session.tracks[trackIndex].name = fileName
            }

        case .stereoPair(let startTrackIndex):
            ensureTrackCount(startTrackIndex + 2)
            let indices = [startTrackIndex, startTrackIndex + 1]
            let wasEmpty = indices.allSatisfy { session.tracks[$0].clips.isEmpty }
            if choice.resolution == .replace {
                for i in indices {
                    session.tracks[i].clips.removeAll()
                }
            }
            let start = choice.resolution == .append
                ? appendStart(forTrackIndices: indices)
                : session.playStartTime
            let pairID = UUID()
            let masks: [OutputMask] = startTrackIndex % 4 == 0
                ? [.out1, .out2]
                : [.out3, .out4]
            let sideLabels = ["L", "R"]
            for (offset, channel) in [0, 1].enumerated() {
                let trackIndex = startTrackIndex + offset
                guard channel < imported.channelCount else { break }
                let trackWasEmpty = session.tracks[trackIndex].clips.isEmpty
                if trackWasEmpty {
                    session.tracks[trackIndex].outputMask = masks[offset]
                }
                session.tracks[trackIndex].clips.append(
                    AudioClip(
                        sourceURL: imported.url,
                        sourceChannel: channel,
                        timelineStart: start,
                        sourceIn: 0,
                        duration: imported.duration,
                        sourceDuration: imported.duration,
                        pairID: pairID
                    )
                )
                if choice.resolution == .replace || wasEmpty || isDefaultTrackName(session.tracks[trackIndex].name) {
                    session.tracks[trackIndex].name = "\(fileName) \(sideLabels[offset])"
                }
            }
        }
    }

    private func isDefaultTrackName(_ name: String) -> Bool {
        name.range(of: #"^Track \d+$"#, options: .regularExpression) != nil
    }

    private func appendStart(forTrackIndices indices: [Int]) -> TimeInterval {
        var end: TimeInterval = session.playStartTime
        for i in indices where session.tracks.indices.contains(i) {
            if let trackEnd = session.tracks[i].clips.map(\.timelineEnd).max() {
                end = max(end, trackEnd)
            }
        }
        return end
    }

    private func ensureTrackCount(_ count: Int) {
        while session.tracks.count < count {
            addTrack()
        }
    }

    private func peakKey(url: URL, channel: Int) -> String {
        "\(url.absoluteString)#\(channel)"
    }

    // MARK: - Document

    func markClean() {
        cleanSession = session
        isDirty = false
    }

    private func refreshDirtyFlag() {
        guard !suppressDirtyTracking else { return }
        let dirty = session != cleanSession
        if isDirty != dirty {
            isDirty = dirty
        }
    }

    func showStatus(_ message: String, duration: TimeInterval = 2.0) {
        statusClearTask?.cancel()
        statusMessage = message
        statusClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }

    /// Standard macOS unsaved-changes alert. Returns whether the caller should proceed.
    /// If the user chooses Save, `performSave` must complete successfully for proceed.
    func confirmDiscardOrSave(performSave: () -> Bool) -> Bool {
        guard isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes you made to “\(documentDisplayName)”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return performSave()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func newSession() {
        muteSnapshot = nil
        clipUndoStack = []
        canUndo = false
        undoGestureOpen = false
        suppressDirtyTracking = true
        session = .blank()
        documentURL = nil
        audioBuffers = [:]
        waveformPeaks = [:]
        engine.stop()
        engine.setPlayStart(0)
        selectedDeviceUID = outputDevices.first?.uid
        session.outputDeviceUID = selectedDeviceUID
        suppressDirtyTracking = false
        reconfigureEngine()
        syncMix()
        markClean()
        statusMessage = nil
    }

    @discardableResult
    func save(to url: URL, announce: Bool = true) -> Bool {
        do {
            try SessionDocumentService.save(session, to: url)
            documentURL = url
            suppressDirtyTracking = true
            session.name = url.deletingPathExtension().lastPathComponent
            suppressDirtyTracking = false
            markClean()
            if announce {
                showStatus("Saved")
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Save to the existing document URL, or present a save panel if untitled.
    @discardableResult
    func saveInteractive(announce: Bool = true) -> Bool {
        if let url = documentURL {
            return save(to: url, announce: announce)
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: SessionDocumentService.fileExtension) ?? .json
        ]
        panel.nameFieldStringValue = "\(session.name).\(SessionDocumentService.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return save(to: url, announce: announce)
    }

    func open(from url: URL) {
        do {
            muteSnapshot = nil
            clipUndoStack = []
            canUndo = false
            undoGestureOpen = false
            let loaded = try SessionDocumentService.load(from: url)
            suppressDirtyTracking = true
            session = loaded
            documentURL = url
            suppressDirtyTracking = false
            engine.stop()
            engine.setPlayStart(loaded.playStartTime)
            if let uid = loaded.outputDeviceUID,
               outputDevices.contains(where: { $0.uid == uid }) {
                selectedDeviceUID = uid
            }
            reconfigureEngine()
            reloadBuffersForSession()
            markClean()
            statusMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadBuffersForSession() {
        isImporting = true
        Task {
            var peaks: [String: [Float]] = [:]
            var buffers: [URL: ImportedAudio] = [:]
            var missing: [URL] = []
            let urls = Array(Set(session.tracks.flatMap(\.clips).map(\.sourceURL)))
            for url in urls {
                _ = url.startAccessingSecurityScopedResource()
                do {
                    let imported = try AudioFileImporter.importFile(
                        at: url,
                        targetSampleRate: session.sampleRate
                    )
                    buffers[url] = imported
                    for channel in 0..<imported.channelCount {
                        peaks[peakKey(url: url, channel: channel)] = imported.peaks[channel]
                    }
                } catch {
                    missing.append(url)
                }
            }

            if !missing.isEmpty {
                let remapped = await MainActor.run { () -> [URL: URL] in
                    self.promptRelinkMissingAudio(missing)
                }
                for (oldURL, newURL) in remapped {
                    _ = newURL.startAccessingSecurityScopedResource()
                    do {
                        let imported = try AudioFileImporter.importFile(
                            at: newURL,
                            targetSampleRate: session.sampleRate
                        )
                        buffers[newURL] = imported
                        for channel in 0..<imported.channelCount {
                            peaks[peakKey(url: newURL, channel: channel)] = imported.peaks[channel]
                        }
                        await MainActor.run {
                            self.remapClipSourceURL(from: oldURL, to: newURL)
                        }
                    } catch {
                        await MainActor.run {
                            self.errorMessage = "Could not open \(newURL.lastPathComponent)"
                        }
                    }
                }
            }

            await MainActor.run {
                self.audioBuffers = buffers
                self.waveformPeaks = peaks
                self.syncMix()
                self.isImporting = false
                let stillMissing = Set(self.session.tracks.flatMap(\.clips).map(\.sourceURL))
                    .filter { buffers[$0] == nil }
                if stillMissing.isEmpty {
                    if !missing.isEmpty {
                        self.showStatus("Audio files linked")
                    }
                } else {
                    let names = stillMissing.map(\.lastPathComponent).sorted().joined(separator: ", ")
                    self.errorMessage = "Still missing: \(names)"
                }
            }
        }
    }

    /// Ask the user to locate missing files. Matching basenames in the same folder are auto-linked.
    @MainActor
    private func promptRelinkMissingAudio(_ missing: [URL]) -> [URL: URL] {
        var remaining = missing
        var remapped: [URL: URL] = [:]

        let intro = NSAlert()
        intro.messageText = missing.count == 1
            ? "Missing audio file"
            : "Missing \(missing.count) audio files"
        intro.informativeText = missing.count == 1
            ? "Locate “\(missing[0].lastPathComponent)” to continue."
            : "Locate each missing file. Other missing files in the same folder are linked automatically."
        intro.addButton(withTitle: "Locate…")
        intro.addButton(withTitle: "Skip All")
        guard intro.runModal() == .alertFirstButtonReturn else {
            return [:]
        }

        while let current = remaining.first {
            let panel = NSOpenPanel()
            panel.message = "Locate “\(current.lastPathComponent)”"
            panel.prompt = "Choose"
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.wav, .mp3, .audio]
            panel.directoryURL = current.deletingLastPathComponent()
            panel.nameFieldStringValue = current.lastPathComponent

            guard panel.runModal() == .OK, let chosen = panel.urls.first else {
                remaining.removeAll { $0 == current }
                continue
            }

            remapped[current] = chosen
            remaining.removeAll { $0 == current }

            // Auto-link other missing files found beside the chosen file(s).
            let searchDirs = Set(panel.urls.map { $0.deletingLastPathComponent() })
            let chosenByName = Dictionary(
                uniqueKeysWithValues: panel.urls.map { ($0.lastPathComponent.lowercased(), $0) }
            )
            var still: [URL] = []
            for url in remaining {
                let name = url.lastPathComponent.lowercased()
                if let match = chosenByName[name] {
                    remapped[url] = match
                    continue
                }
                var found: URL?
                for dir in searchDirs {
                    let candidate = dir.appendingPathComponent(url.lastPathComponent)
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        found = candidate
                        break
                    }
                }
                if let found {
                    remapped[url] = found
                } else {
                    still.append(url)
                }
            }
            remaining = still

            if !remaining.isEmpty {
                let more = NSAlert()
                more.messageText = "\(remaining.count) file(s) still missing"
                more.informativeText = remaining.map(\.lastPathComponent).joined(separator: "\n")
                more.addButton(withTitle: "Locate Next…")
                more.addButton(withTitle: "Skip Rest")
                if more.runModal() != .alertFirstButtonReturn {
                    break
                }
            }
        }

        return remapped
    }

    private func remapClipSourceURL(from oldURL: URL, to newURL: URL) {
        for t in session.tracks.indices {
            for c in session.tracks[t].clips.indices {
                if session.tracks[t].clips[c].sourceURL == oldURL {
                    session.tracks[t].clips[c].sourceURL = newURL
                }
            }
        }
    }

    private func reconfigureEngine() {
        do {
            try engine.configureOutput(
                deviceUID: selectedDeviceUID,
                preferredSampleRate: session.sampleRate
            )
            syncMix()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncMix() {
        engine.updateMix(session: session, buffers: audioBuffers)
    }
}
