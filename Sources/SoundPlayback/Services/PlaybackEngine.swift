import Foundation

/// Placeholder for the realtime engine. Device selection and session state live here first;
/// buffer rendering / Core Audio I/O comes next.
enum TransportState: Equatable {
    case stopped
    case playing
    case paused
}

@MainActor
final class PlaybackEngine: ObservableObject {
    @Published private(set) var transport: TransportState = .stopped
    @Published var playheadTime: TimeInterval = 0

    private(set) var playStartTime: TimeInterval = 0

    func setPlayStart(_ time: TimeInterval) {
        playStartTime = max(0, time)
        if transport != .playing {
            playheadTime = playStartTime
        }
    }

    func play() {
        if transport == .stopped {
            playheadTime = playStartTime
        }
        transport = .playing
    }

    func pause() {
        guard transport == .playing else { return }
        transport = .paused
    }

    func stop() {
        transport = .stopped
        playheadTime = playStartTime
    }

    func togglePlayStop() {
        if transport == .playing {
            stop()
        } else {
            play()
        }
    }
}
