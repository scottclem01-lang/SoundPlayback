import Foundation

enum ImportPlacementMode: Equatable {
    /// Single track index (0-based).
    case mono(trackIndex: Int)
    /// Locked stereo pair starting at even track index (0, 2, 4…).
    case stereoPair(startTrackIndex: Int)
}

enum ImportConflictResolution: Equatable {
    case replace
    case append
}

/// One file waiting for the user to choose destination / replace-append.
struct PendingImport: Identifiable, Equatable {
    let id: UUID
    let url: URL
    /// 1 = mono placement, 2 = locked stereo pair (files with more channels still place as stereo).
    let placementChannels: Int

    init(id: UUID = UUID(), url: URL, sourceChannelCount: Int) {
        self.id = id
        self.url = url
        self.placementChannels = sourceChannelCount >= 2 ? 2 : 1
    }

    var isStereo: Bool { placementChannels == 2 }
    var displayName: String { url.lastPathComponent }
}

struct ImportPlacementChoice: Equatable {
    var mode: ImportPlacementMode
    var resolution: ImportConflictResolution
}
