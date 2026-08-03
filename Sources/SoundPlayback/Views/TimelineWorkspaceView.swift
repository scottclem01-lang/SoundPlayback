import SwiftUI

struct TimelineWorkspaceView: View {
    @ObservedObject var viewModel: SessionViewModel
    @ObservedObject var engine: PlaybackEngine

    @State private var pinchBaselinePPS: Double?
    @State private var pinchAnchorInViewport: CGFloat?
    @State private var scrollOffsetX: CGFloat = 0
    @State private var scrollOffsetY: CGFloat = 0
    @State private var viewportWidth: CGFloat = 800
    @State private var scrollRequest: TimelineScrollRequest?
    /// Logical page-mode window origin (timeline X). Updated on jumps and user scroll so
    /// follow keeps working even before the scroll view has reported an offset.
    @State private var pageWindowOriginX: CGFloat = 0
    @State private var dragGhost: ClipDragGhost?

    private var timelineDuration: TimeInterval {
        let clipEnd = viewModel.session.tracks
            .flatMap(\.clips)
            .map(\.timelineEnd)
            .max() ?? 0
        let markerEnd = viewModel.session.markers.map(\.time).max() ?? 0
        // At least 10 minutes of ruler so empty / short sessions still scroll usefully.
        return max(600, clipEnd + 10, markerEnd + 10, engine.playheadTime + 10)
    }

    private var timelineWidth: CGFloat {
        CGFloat(timelineDuration * viewModel.pixelsPerSecond)
    }

    private var contentHeight: CGFloat {
        SPTheme.rulerHeight + CGFloat(viewModel.session.tracks.count) * SPTheme.trackHeight
    }

    private var playheadTimelineX: CGFloat {
        CGFloat(engine.playheadTime * viewModel.pixelsPerSecond)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                AlignedTimelineHost(
                    headerWidth: SPTheme.headerWidth,
                    timelineWidth: timelineWidth,
                    contentHeight: contentHeight,
                    scrollRequest: scrollRequest,
                    onOffsetChange: { x, y in
                        scrollOffsetX = x
                        scrollOffsetY = y
                        // Keep the page window in sync with actual scroll (user drag or jump settle).
                        pageWindowOriginX = x
                    },
                    header: { headerDocument },
                    timeline: { timelineDocument }
                )
                .onAppear { viewportWidth = max(1, geo.size.width - SPTheme.headerWidth) }
                .onChange(of: geo.size.width) { _, w in
                    viewportWidth = max(1, w - SPTheme.headerWidth)
                }
            }

            HStack {
                Button("Add Track") { viewModel.addTrack() }
                    .buttonStyle(.borderless)
                if viewModel.isImporting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Importing…")
                        .font(.caption)
                        .foregroundStyle(SPTheme.textSecondary)
                }
                Spacer()
                Text("\(Int(viewModel.pixelsPerSecond)) px/s")
                    .font(.caption)
                    .foregroundStyle(SPTheme.textSecondary)
            }
            .padding(8)
            .background(SPTheme.panel)
        }
        .gesture(pinchZoomGesture)
        .onChange(of: engine.transport) { _, transport in
            handleTransportChange(transport)
        }
        .onChange(of: engine.playheadTime) { _, _ in
            guard engine.transport == .playing else { return }
            updateFollowScroll()
        }
        .onChange(of: viewModel.activelyScroll) { _, enabled in
            guard engine.transport == .playing else { return }
            if enabled {
                updateFollowScroll()
            }
        }
        .onChange(of: viewModel.playheadFocusToken) { _, _ in
            // Marker jumps and stop both request focus; always snap to playhead.
            focusPlayhead(onlyIfNeeded: false)
        }
    }

    private var pinchZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if pinchBaselinePPS == nil {
                    pinchBaselinePPS = viewModel.pixelsPerSecond
                    // Keep playhead fixed on screen while zooming.
                    pinchAnchorInViewport = playheadTimelineX - scrollOffsetX
                }
                guard let baselinePPS = pinchBaselinePPS,
                      let anchor = pinchAnchorInViewport else { return }

                viewModel.zoomBy(factor: Double(scale), baseline: baselinePPS)

                let newPlayheadX = CGFloat(engine.playheadTime * viewModel.pixelsPerSecond)
                let newScrollX = max(0, newPlayheadX - anchor)
                scrollOffsetX = newScrollX
                scrollRequest = .to(CGPoint(x: newScrollX, y: scrollOffsetY))
            }
            .onEnded { _ in
                pinchBaselinePPS = nil
                pinchAnchorInViewport = nil
            }
    }

    private var headerDocument: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(width: SPTheme.headerWidth, height: SPTheme.rulerHeight)
                .background(SPTheme.panel)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(SPTheme.border).frame(height: 1)
                }
                .overlay(alignment: .trailing) {
                    Rectangle().fill(SPTheme.border).frame(width: 1)
                }

            ForEach(viewModel.session.tracks) { track in
                TrackHeaderView(
                    track: track,
                    availableOutputs: viewModel.availableOutputCount,
                    canDelete: viewModel.session.tracks.count > 1,
                    canBeginRename: engine.transport == .stopped,
                    onVolume: { viewModel.setVolume(trackID: track.id, volume: $0) },
                    onMute: { viewModel.setMute(trackID: track.id, muted: $0) },
                    onSolo: { viewModel.setSolo(trackID: track.id, enabled: $0) },
                    onToggleOutput: { channel in
                        viewModel.toggleOutput(trackID: track.id, channel: channel)
                    },
                    onRename: { viewModel.renameTrack(id: track.id, name: $0) },
                    onRenameEditingChanged: { editing in
                        viewModel.isEditingTrackName = editing
                    },
                    onDelete: { viewModel.deleteTrack(id: track.id) }
                )
                .frame(width: SPTheme.headerWidth, height: SPTheme.trackHeight)
            }
        }
        .frame(width: SPTheme.headerWidth, height: contentHeight, alignment: .topLeading)
        .background(SPTheme.panel)
    }

    private var timelineDocument: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                MarkerRulerView(
                    markers: viewModel.session.markers,
                    playheadTime: engine.playheadTime,
                    playStartTime: viewModel.session.playStartTime,
                    pixelsPerSecond: viewModel.pixelsPerSecond,
                    contentWidth: timelineWidth,
                    timelineOrigin: viewModel.session.timelineOrigin,
                    onSeek: { viewModel.setPlayStart(at: $0) },
                    onScrub: { engine.scrubPlayhead(to: $0) },
                    onMoveMarker: { id, time in viewModel.moveMarker(id: id, to: time) },
                    onDeleteMarker: { id in viewModel.deleteMarker(id: id) },
                    onSetMarkerNote: { id, note in viewModel.setMarkerNote(id: id, note: note) },
                    onNoteEditingChanged: { editing in viewModel.isEditingMarkerNote = editing }
                )
                .frame(width: timelineWidth, height: SPTheme.rulerHeight)

                ForEach(Array(viewModel.session.tracks.enumerated()), id: \.element.id) { trackIndex, track in
                    TimelineLaneView(
                        track: track,
                        trackIndex: trackIndex,
                        allTracks: viewModel.session.tracks,
                        peaksProvider: { viewModel.peaks(for: $0) },
                        pixelsPerSecond: viewModel.pixelsPerSecond,
                        contentWidth: timelineWidth,
                        playheadTime: engine.playheadTime,
                        timelineOrigin: viewModel.session.timelineOrigin,
                        selectedClipIDs: viewModel.selectedClipIDs,
                        snapMoveStart: { clip, start in viewModel.snappedMoveStart(for: clip, proposedStart: start) },
                        snapTrimStart: { clip, start in viewModel.snappedTrimStart(for: clip, proposedStart: start) },
                        snapTrimEnd: { clip, end in viewModel.snappedTrimEnd(for: clip, proposedEnd: end) },
                        onSelectClip: { id, additive in viewModel.selectClip(id: id, additive: additive) },
                        onEditGeneratedClip: { viewModel.beginEditGeneratedClip(clipID: $0) },
                        onSetClipStartTime: { id, raw, moveMarkers in
                            viewModel.setClipStartTime(clipID: id, raw: raw, moveMarkers: moveMarkers)
                        },
                        onClipStartEditingChanged: { editing in viewModel.isEditingClipStart = editing },
                        onEmptyLaneClick: { time in
                            viewModel.clearClipSelection()
                            viewModel.setPlayStart(at: time)
                        },
                        onGhostChange: { dragGhost = $0 },
                        onBeginEdit: { viewModel.beginClipEdit() },
                        onEndEdit: { viewModel.endClipEdit() },
                        onMoveClip: { clipID, toTrackID, start in
                            viewModel.moveClip(clipID: clipID, toTrackID: toTrackID, timelineStart: start)
                        },
                        onTrimStart: { clipID, start in
                            viewModel.trimClipStart(clipID: clipID, newTimelineStart: start)
                        },
                        onTrimEnd: { clipID, end in
                            viewModel.trimClipEnd(clipID: clipID, newTimelineEnd: end)
                        }
                    )
                    .frame(width: timelineWidth, height: SPTheme.trackHeight)
                }
            }

            if let ghost = dragGhost {
                let x = ghost.timelineStart * viewModel.pixelsPerSecond
                let y = SPTheme.rulerHeight + CGFloat(ghost.trackIndex) * SPTheme.trackHeight + 6
                let w = max(8, ghost.duration * viewModel.pixelsPerSecond)
                let h = SPTheme.trackHeight - 12
                RoundedRectangle(cornerRadius: 3)
                    .stroke(SPTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(SPTheme.accent.opacity(0.14))
                    )
                    .frame(width: w, height: h)
                    .offset(x: x, y: y)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: timelineWidth, height: contentHeight, alignment: .topLeading)
        .background(SPTheme.canvas)
    }

    private func handleTransportChange(_ transport: TransportState) {
        switch transport {
        case .playing:
            // Anchor the page window to wherever we currently are so the first exit can jump.
            pageWindowOriginX = scrollOffsetX
            updateFollowScroll()
        case .stopped:
            focusPlayhead(onlyIfNeeded: true)
        case .paused:
            break
        }
    }

    private func focusPlayhead(onlyIfNeeded: Bool) {
        let ph = playheadTimelineX
        let vw = max(viewportWidth, 1)
        let margin: CGFloat = 4
        let origin = pageWindowOriginX
        let visible = ph >= origin + margin && ph <= origin + vw - margin
        if onlyIfNeeded, visible { return }
        let targetX = max(0, ph - vw * 0.25)
        pageWindowOriginX = targetX
        scrollOffsetX = targetX
        scrollRequest = .to(CGPoint(x: targetX, y: scrollOffsetY))
    }

    private func updateFollowScroll() {
        let ph = playheadTimelineX
        let vw = max(viewportWidth, 1)

        if viewModel.activelyScroll {
            let targetX = max(0, ph - vw * 0.5)
            pageWindowOriginX = targetX
            scrollOffsetX = targetX
            scrollRequest = .to(CGPoint(x: targetX, y: scrollOffsetY))
            return
        }

        // Page mode: jump when the playhead leaves the current page window.
        // Use pageWindowOriginX (not only scrollOffsetX) so cold-start / never-scrolled
        // and post-marker-jump cases still page correctly.
        let visibleMinX = pageWindowOriginX
        let visibleMaxX = pageWindowOriginX + vw
        guard ph > visibleMaxX || ph < visibleMinX else { return }

        let targetX = max(0, ph - vw * 0.25)
        pageWindowOriginX = targetX
        scrollOffsetX = targetX
        scrollRequest = .to(CGPoint(x: targetX, y: scrollOffsetY))
    }
}
