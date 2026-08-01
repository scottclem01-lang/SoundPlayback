import Foundation

struct ClipDragGhost: Equatable {
    var clipID: UUID
    var timelineStart: TimeInterval
    var duration: TimeInterval
    var trackIndex: Int
}
