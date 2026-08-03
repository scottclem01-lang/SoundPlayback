import SwiftUI

enum SPTheme {
    static let canvas = Color(red: 0.11, green: 0.12, blue: 0.13)
    static let panel = Color(red: 0.16, green: 0.17, blue: 0.18)
    static let trackLane = Color(red: 0.14, green: 0.15, blue: 0.16)
    static let border = Color.white.opacity(0.12)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let accent = Color(red: 0.35, green: 0.72, blue: 0.55)
    static let clipFill = Color(red: 0.22, green: 0.45, blue: 0.38)
    /// Warm amber — intro click / metronome clips (double-click to edit tempo).
    static let clipFillClicks = Color(red: 0.62, green: 0.42, blue: 0.16)
    /// Violet — thump / tone-pulse clips (double-click to edit tempo).
    static let clipFillThump = Color(red: 0.42, green: 0.30, blue: 0.58)
    static let trackLaneGenerated = Color(red: 0.17, green: 0.15, blue: 0.20)
    static let playhead = Color(red: 0.95, green: 0.55, blue: 0.25)
    static let marker = Color(red: 0.95, green: 0.78, blue: 0.30)
    static let headerWidth: CGFloat = 196
    static let trackHeight: CGFloat = 72
    /// Tall enough for marker badges on top and tick labels along the bottom.
    static let rulerHeight: CGFloat = 40
}
