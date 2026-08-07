import Foundation

enum GeneratedPlacementTrack: Equatable, Hashable {
    case existing(Int)
    case newTrack
}

struct EditGeneratedClipRequest: Identifiable, Equatable {
    let id: UUID // clip id
    var kind: GeneratedClipKind
    var title: String
    var tempoBPM: Double
    var clickCount: Int
    var frequencyHz: Double
    var thumpTenths: Int
    var trackLengthSeconds: Double
    var timecodeFrameRate: TimecodeFrameRate
    var timecodeStart: String
    var lockToTimeline: Bool
}

struct IntroClicksRequest: Identifiable, Equatable {
    let id = UUID()
    var tempoBPM: Double = 120
    var clickCount: Int = 4
    var track: GeneratedPlacementTrack = .newTrack
}

struct ThumpTrackRequest: Identifiable, Equatable {
    let id = UUID()
    var tempoBPM: Double = 120
    var frequencyHz: Double = 55
    var thumpTenths: Int = 2
    var trackLengthSeconds: Double = 16
    var track: GeneratedPlacementTrack = .newTrack
}

struct TimecodeTrackRequest: Identifiable, Equatable {
    let id = UUID()
    var frameRate: TimecodeFrameRate = .fps24
    var startTimecode: String = "00:00:00:00"
    var lengthSeconds: Double = 60
    var lockToTimeline: Bool = true
    var track: GeneratedPlacementTrack = .newTrack
}
