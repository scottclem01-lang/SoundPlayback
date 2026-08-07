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
    /// Display origin for the ruler / clocks. Internal positions stay 0-based;
    /// shown time = internal + timelineOrigin (e.g. origin 1:00:00 → left edge reads 1:00:00).
    var timelineOrigin: TimeInterval
    /// Project frame rate — timeline clocks and locked LTC use this.
    var timelineFrameRate: TimecodeFrameRate

    enum CodingKeys: String, CodingKey {
        case version, name, sampleRate, tracks, markers, outputDeviceUID, playStartTime, timelineOrigin, timelineFrameRate
    }

    init(
        version: Int = 1,
        name: String,
        sampleRate: Double,
        tracks: [Track],
        markers: [TimelineMarker],
        outputDeviceUID: String?,
        playStartTime: TimeInterval,
        timelineOrigin: TimeInterval = 0,
        timelineFrameRate: TimecodeFrameRate = .fps24
    ) {
        self.version = version
        self.name = name
        self.sampleRate = sampleRate
        self.tracks = tracks
        self.markers = markers
        self.outputDeviceUID = outputDeviceUID
        self.playStartTime = playStartTime
        self.timelineOrigin = timelineOrigin
        self.timelineFrameRate = timelineFrameRate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        name = try c.decode(String.self, forKey: .name)
        sampleRate = try c.decode(Double.self, forKey: .sampleRate)
        tracks = try c.decode([Track].self, forKey: .tracks)
        markers = try c.decode([TimelineMarker].self, forKey: .markers)
        outputDeviceUID = try c.decodeIfPresent(String.self, forKey: .outputDeviceUID)
        playStartTime = try c.decodeIfPresent(TimeInterval.self, forKey: .playStartTime) ?? 0
        timelineOrigin = try c.decodeIfPresent(TimeInterval.self, forKey: .timelineOrigin) ?? 0
        if let raw = try c.decodeIfPresent(String.self, forKey: .timelineFrameRate),
           let rate = TimecodeFrameRate(rawValue: raw) {
            timelineFrameRate = rate
        } else {
            timelineFrameRate = .fps24
        }
    }

    static func blank(trackCount: Int = 4) -> PlaybackSession {
        PlaybackSession(
            name: "Untitled",
            sampleRate: 48_000,
            tracks: (0..<trackCount).map { Track(name: "Track \($0 + 1)") },
            markers: [],
            outputDeviceUID: nil,
            playStartTime: 0,
            timelineOrigin: 0,
            timelineFrameRate: .fps24
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
    case timecode
}

struct ClipGeneration: Codable, Equatable {
    var kind: GeneratedClipKind
    var tempoBPM: Double
    var clickCount: Int?
    var frequencyHz: Double?
    var thumpTenths: Int?
    var trackLengthSeconds: Double?
    /// SMPTE LTC rate raw value (`TimecodeFrameRate.rawValue`).
    var timecodeFrameRate: String?
    var timecodeStartHours: Int?
    var timecodeStartMinutes: Int?
    var timecodeStartSeconds: Int?
    var timecodeStartFrames: Int?
    /// When true, LTC at the clip’s left edge matches the timeline clock.
    var lockToTimeline: Bool?

    static func introClicks(tempoBPM: Double, clickCount: Int) -> ClipGeneration {
        ClipGeneration(
            kind: .introClicks,
            tempoBPM: tempoBPM,
            clickCount: clickCount,
            frequencyHz: nil,
            thumpTenths: nil,
            trackLengthSeconds: nil,
            timecodeFrameRate: nil,
            timecodeStartHours: nil,
            timecodeStartMinutes: nil,
            timecodeStartSeconds: nil,
            timecodeStartFrames: nil,
            lockToTimeline: nil
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
            trackLengthSeconds: trackLengthSeconds,
            timecodeFrameRate: nil,
            timecodeStartHours: nil,
            timecodeStartMinutes: nil,
            timecodeStartSeconds: nil,
            timecodeStartFrames: nil,
            lockToTimeline: nil
        )
    }

    static func timecode(
        frameRate: TimecodeFrameRate,
        start: SMPTEComponents,
        trackLengthSeconds: Double,
        lockToTimeline: Bool
    ) -> ClipGeneration {
        let c = start.clamped(to: frameRate)
        return ClipGeneration(
            kind: .timecode,
            tempoBPM: 0,
            clickCount: nil,
            frequencyHz: nil,
            thumpTenths: nil,
            trackLengthSeconds: trackLengthSeconds,
            timecodeFrameRate: frameRate.rawValue,
            timecodeStartHours: c.hours,
            timecodeStartMinutes: c.minutes,
            timecodeStartSeconds: c.seconds,
            timecodeStartFrames: c.frames,
            lockToTimeline: lockToTimeline
        )
    }

    var resolvedFrameRate: TimecodeFrameRate {
        TimecodeFrameRate(rawValue: timecodeFrameRate ?? "") ?? .fps24
    }

    var resolvedStartComponents: SMPTEComponents {
        SMPTEComponents(
            hours: timecodeStartHours ?? 0,
            minutes: timecodeStartMinutes ?? 0,
            seconds: timecodeStartSeconds ?? 0,
            frames: timecodeStartFrames ?? 0
        )
    }

    var displayName: String {
        switch kind {
        case .introClicks: return "Intro Clicks"
        case .thump: return "Thump"
        case .timecode: return "Timecode"
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
    /// Optional label shown next to the mark (intro, chorus 1, …).
    var note: String
    /// Favorited marks highlight in the marks list.
    var isFavorite: Bool

    init(id: UUID = UUID(), number: Int, time: TimeInterval, note: String = "", isFavorite: Bool = false) {
        self.id = id
        self.number = number
        self.time = time
        self.note = note
        self.isFavorite = isFavorite
    }

    enum CodingKeys: String, CodingKey {
        case id, number, time, note, isFavorite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        number = try c.decode(Int.self, forKey: .number)
        time = try c.decode(TimeInterval.self, forKey: .time)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
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

    /// US keyboard: `1`→1 … `0`→10, and `!`→11 … `)`→20.
    static func numberForCharacter(_ raw: Character) -> Int? {
        switch raw {
        case "1": return 1
        case "2": return 2
        case "3": return 3
        case "4": return 4
        case "5": return 5
        case "6": return 6
        case "7": return 7
        case "8": return 8
        case "9": return 9
        case "0": return 10
        case "!": return 11
        case "@": return 12
        case "#": return 13
        case "$": return 14
        case "%": return 15
        case "^": return 16
        case "&": return 17
        case "*": return 18
        case "(": return 19
        case ")": return 20
        default: return nil
        }
    }

    /// Mac number-row key codes → digit 0–9 (keyCode 29 = 0).
    static func digitForKeyCode(_ keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        case 25: return 9
        case 29: return 0
        default: return nil
        }
    }
}
