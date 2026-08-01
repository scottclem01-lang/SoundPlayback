import Foundation

/// Serializable project document (.soundplayback).
struct PlaybackSession: Codable, Equatable {
    var version: Int = 1
    var name: String
    var sampleRate: Double
    var tracks: [Track]
    var markers: [TimelineMarker]
    /// Output device UID last selected for this session (may be nil / unavailable on reopen).
    var outputDeviceUID: String?
    /// Playhead start point used after Stop (seconds from timeline zero).
    var playStartTime: TimeInterval

    static func blank(trackCount: Int = 4) -> PlaybackSession {
        PlaybackSession(
            name: "Untitled",
            sampleRate: 48_000,
            tracks: (0..<trackCount).map { Track(name: "Track \($0 + 1)") },
            markers: [],
            outputDeviceUID: nil,
            playStartTime: 0
        )
    }
}

struct Track: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var volume: Double
    var isMuted: Bool
    var isSoloed: Bool
    /// Which physical outputs (1…4) this track feeds. Any combination allowed.
    var outputMask: OutputMask
    var clips: [AudioClip]

    init(
        id: UUID = UUID(),
        name: String,
        volume: Double = 0.8,
        isMuted: Bool = false,
        isSoloed: Bool = false,
        outputMask: OutputMask = .outs12,
        clips: [AudioClip] = []
    ) {
        self.id = id
        self.name = name
        self.volume = volume
        self.isMuted = isMuted
        self.isSoloed = isSoloed
        self.outputMask = outputMask
        self.clips = clips
    }
}

/// Bitmask for interface outs 1–4. Multiple bits may be set.
struct OutputMask: OptionSet, Codable, Equatable, Hashable {
    let rawValue: Int

    static let out1 = OutputMask(rawValue: 1 << 0)
    static let out2 = OutputMask(rawValue: 1 << 1)
    static let out3 = OutputMask(rawValue: 1 << 2)
    static let out4 = OutputMask(rawValue: 1 << 3)

    static let outs12: OutputMask = [.out1, .out2]
    static let all: OutputMask = [.out1, .out2, .out3, .out4]

    static func channel(_ index: Int) -> OutputMask {
        switch index {
        case 1: return .out1
        case 2: return .out2
        case 3: return .out3
        case 4: return .out4
        default: return []
        }
    }
}

/// How a clip was synthesized (nil = imported audio). Persisted so tempo can be re-edited.
enum GeneratedClipKind: String, Codable, Equatable {
    case introClicks
    case thump
}

struct ClipGeneration: Codable, Equatable {
    var kind: GeneratedClipKind
    var tempoBPM: Double
    var clickCount: Int?
    var frequencyHz: Double?
    var thumpTenths: Int?
    var trackLengthSeconds: Double?

    static func introClicks(tempoBPM: Double, clickCount: Int) -> ClipGeneration {
        ClipGeneration(
            kind: .introClicks,
            tempoBPM: tempoBPM,
            clickCount: clickCount,
            frequencyHz: nil,
            thumpTenths: nil,
            trackLengthSeconds: nil
        )
    }

    static func thump(
        tempoBPM: Double,
        frequencyHz: Double,
        thumpTenths: Int,
        trackLengthSeconds: Double
    ) -> ClipGeneration {
        ClipGeneration(
            kind: .thump,
            tempoBPM: tempoBPM,
            clickCount: nil,
            frequencyHz: frequencyHz,
            thumpTenths: thumpTenths,
            trackLengthSeconds: trackLengthSeconds
        )
    }

    var displayName: String {
        switch kind {
        case .introClicks: return "Intro Clicks"
        case .thump: return "Thump"
        }
    }
}

/// Mono clip on the timeline. Stereo imports create two paired clips (L/R) on adjacent tracks.
struct AudioClip: Identifiable, Codable, Equatable {
    var id: UUID
    /// Absolute path to source file (WAV/MP3).
    var sourceURL: URL
    /// 0 = left (or mono), 1 = right for stereo sources.
    var sourceChannel: Int
    /// Timeline position of the audible start (seconds).
    var timelineStart: TimeInterval
    /// Offset into the source file where playback begins (seconds).
    var sourceIn: TimeInterval
    /// Duration of the audible region (seconds). Expanding is capped by remaining source.
    var duration: TimeInterval
    var sourceDuration: TimeInterval
    /// When set, this clip is locked to its stereo partner (same id on both).
    var pairID: UUID?
    /// Present for synthesized click/thump clips.
    var generation: ClipGeneration?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceChannel: Int = 0,
        timelineStart: TimeInterval = 0,
        sourceIn: TimeInterval = 0,
        duration: TimeInterval,
        sourceDuration: TimeInterval,
        pairID: UUID? = nil,
        generation: ClipGeneration? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceChannel = sourceChannel
        self.timelineStart = timelineStart
        self.sourceIn = sourceIn
        self.duration = duration
        self.sourceDuration = sourceDuration
        self.pairID = pairID
        self.generation = generation
    }

    var timelineEnd: TimeInterval { timelineStart + duration }

    /// How far the left edge can expand (seconds of unused head).
    var maxExpandLeft: TimeInterval { sourceIn }

    /// How far the right edge can expand (seconds of unused tail).
    var maxExpandRight: TimeInterval { max(0, sourceDuration - sourceIn - duration) }

    var isGenerated: Bool { generation != nil }
}

struct TimelineMarker: Identifiable, Codable, Equatable, Comparable {
    var id: UUID
    /// Sequential display number starting at 1.
    var number: Int
    var time: TimeInterval

    init(id: UUID = UUID(), number: Int, time: TimeInterval) {
        self.id = id
        self.number = number
        self.time = time
    }

    static func < (lhs: TimelineMarker, rhs: TimelineMarker) -> Bool {
        lhs.time < rhs.time
    }
}

extension TimelineMarker {
    /// Keyboard digit 0–9 → marker number, with optional Shift for 11–20.
    static func numberForKey(digit: Int, shift: Bool) -> Int? {
        guard (0...9).contains(digit) else { return nil }
        let base = digit == 0 ? 10 : digit
        return shift ? base + 10 : base
    }
}
