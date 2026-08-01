import SwiftUI

struct TimelineWorkspaceView: View {
    @ObservedObject var viewModel: SessionViewModel
    @ObservedObject var engine: PlaybackEngine

    private var timelineDuration: TimeInterval {
        let clipEnd = viewModel.session.tracks
            .flatMap(\.clips)
            .map(\.timelineEnd)
            .max() ?? 0
        let markerEnd = viewModel.session.markers.map(\.time).max() ?? 0
        return max(60, clipEnd + 10, markerEnd + 10, engine.playheadTime + 10)
    }

    private var contentWidth: CGFloat {
        CGFloat(timelineDuration * viewModel.pixelsPerSecond)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: SPTheme.headerWidth, height: SPTheme.rulerHeight)
                    .background(SPTheme.panel)
                    .overlay(Rectangle().stroke(SPTheme.border, lineWidth: 1))

                ScrollView(.horizontal, showsIndicators: true) {
                    MarkerRulerView(
                        markers: viewModel.session.markers,
                        playheadTime: engine.playheadTime,
                        playStartTime: viewModel.session.playStartTime,
                        pixelsPerSecond: viewModel.pixelsPerSecond,
                        contentWidth: contentWidth,
                        onSeek: { viewModel.setPlayStart(at: $0) },
                        onScrub: { engine.playheadTime = max(0, $0) }
                    )
                }
            }

            ScrollView([.vertical, .horizontal]) {
                VStack(spacing: 0) {
                    ForEach($viewModel.session.tracks) { $track in
                        HStack(spacing: 0) {
                            TrackHeaderView(
                                track: $track,
                                availableOutputs: viewModel.availableOutputCount,
                                onToggleOutput: { channel in
                                    viewModel.toggleOutput(trackID: track.id, channel: channel)
                                }
                            )
                            TimelineLaneView(
                                track: track,
                                pixelsPerSecond: viewModel.pixelsPerSecond,
                                contentWidth: contentWidth,
                                playheadTime: engine.playheadTime
                            )
                        }
                    }
                }
            }

            HStack {
                Button("Add Track") { viewModel.addTrack() }
                    .buttonStyle(.borderless)
                Spacer()
                Text("\(viewModel.session.tracks.count) tracks · M marker · 1–0 jump · Shift+digit = 11–20")
                    .font(.caption)
                    .foregroundStyle(SPTheme.textSecondary)
            }
            .padding(8)
            .background(SPTheme.panel)
        }
    }
}
