import SwiftUI

/// Owns the marks list and only refreshes when the session view-model changes —
/// not on every playhead tick (which was crashing scroll during playback).
struct MarksListSidebar: View {
    @ObservedObject var viewModel: SessionViewModel

    private var activeMarkNumber: Int? {
        let t = viewModel.session.playStartTime
        return viewModel.session.markers.first(where: { abs($0.time - t) < 0.001 })?.number
    }

    var body: some View {
        MarksListPanel(
            markers: viewModel.session.markers,
            timelineOrigin: viewModel.session.timelineOrigin,
            timelineFrameRate: viewModel.session.timelineFrameRate,
            activeNumber: activeMarkNumber,
            onJump: { viewModel.jumpToMarker(number: $0) },
            onSetFavorite: { id, fav in viewModel.setMarkerFavorite(id: id, isFavorite: fav) }
        )
    }
}

/// Vertical directory of timeline marks, docked left of the track headers.
struct MarksListPanel: View {
    let markers: [TimelineMarker]
    let timelineOrigin: TimeInterval
    let timelineFrameRate: TimecodeFrameRate
    /// Mark number under the play-start (highlight); nil when none.
    let activeNumber: Int?
    let onJump: (Int) -> Void
    let onSetFavorite: (UUID, Bool) -> Void

    private var ordered: [TimelineMarker] {
        markers.sorted { a, b in
            if a.isFavorite != b.isFavorite {
                return a.isFavorite && !b.isFavorite
            }
            return a.time < b.time
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Marks")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SPTheme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: SPTheme.rulerHeight, maxHeight: SPTheme.rulerHeight)
                .background(SPTheme.panel)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(SPTheme.border).frame(height: 1)
                }

            if ordered.isEmpty {
                Text("No marks")
                    .font(.system(size: 11))
                    .foregroundStyle(SPTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(ordered) { marker in
                            MarksListRow(
                                marker: marker,
                                timelineOrigin: timelineOrigin,
                                timelineFrameRate: timelineFrameRate,
                                isActive: marker.number == activeNumber,
                                onJump: { onJump(marker.number) },
                                onSetFavorite: { onSetFavorite(marker.id, $0) }
                            )
                            .id(marker.id)
                        }
                    }
                }
            }
        }
        .frame(width: SPTheme.marksPanelWidth)
        .background(SPTheme.panel)
        .overlay(alignment: .trailing) {
            Rectangle().fill(SPTheme.border).frame(width: 1)
        }
    }
}

private struct MarksListRow: View {
    let marker: TimelineMarker
    let timelineOrigin: TimeInterval
    let timelineFrameRate: TimecodeFrameRate
    let isActive: Bool
    let onJump: () -> Void
    let onSetFavorite: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onJump) {
            HStack(alignment: .top, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Text("\(marker.number)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .frame(width: 22, height: 18)
                        .background(marker.isFavorite ? SPTheme.markerFavorite : SPTheme.marker)
                        .cornerRadius(3)

                    if marker.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Color.white)
                            .offset(x: 4, y: -4)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(marker.note.isEmpty ? "—" : marker.note)
                        .font(.system(size: 11, weight: marker.note.isEmpty ? .regular : .medium))
                        .foregroundStyle(marker.note.isEmpty ? SPTheme.textSecondary : SPTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(TimeFormat.timecode(marker.time + timelineOrigin, rate: timelineFrameRate))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(SPTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .overlay(alignment: .leading) {
                if marker.isFavorite {
                    Rectangle()
                        .fill(SPTheme.markerFavorite)
                        .frame(width: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(marker.isFavorite ? "Unfavorite" : "Favorite") {
                onSetFavorite(!marker.isFavorite)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(SPTheme.border.opacity(0.6)).frame(height: 1)
        }
    }

    private var rowBackground: Color {
        if marker.isFavorite {
            return SPTheme.markerFavorite.opacity(isActive ? 0.38 : 0.28)
        }
        if isActive {
            return SPTheme.marker.opacity(0.18)
        }
        if isHovered {
            return Color.white.opacity(0.06)
        }
        return Color.clear
    }

    private var helpText: String {
        let note = marker.note.isEmpty ? "Mark \(marker.number)" : marker.note
        let fav = marker.isFavorite ? " · favorite" : ""
        return "Jump to \(note)\(fav)"
    }
}
