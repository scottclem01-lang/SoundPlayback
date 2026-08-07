import Foundation

/// SMPTE frame-rate presets for Linear Timecode (LTC) generation.
enum TimecodeFrameRate: String, Codable, CaseIterable, Identifiable, Equatable {
    case fps2398 = "23.98"
    case fps24 = "24"
    case fps2997DF = "29.97"
    case fps2997NDF = "29.97 NDF"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// Real-time frames per second (bit-rate / 80).
    var framesPerSecond: Double {
        switch self {
        case .fps2398: return 24_000.0 / 1_001.0
        case .fps24: return 24
        case .fps2997DF, .fps2997NDF: return 30_000.0 / 1_001.0
        }
    }

    /// Discrete frame count per second in the HH:MM:SS:FF numbers (24 or 30).
    var countingFPS: Int {
        switch self {
        case .fps2398, .fps24: return 24
        case .fps2997DF, .fps2997NDF: return 30
        }
    }

    var isDropFrame: Bool { self == .fps2997DF }

    /// Separator between seconds and frames in display strings.
    var frameSeparator: Character { isDropFrame ? ";" : ":" }
}

struct SMPTEComponents: Equatable {
    var hours: Int
    var minutes: Int
    var seconds: Int
    var frames: Int

    static let zero = SMPTEComponents(hours: 0, minutes: 0, seconds: 0, frames: 0)

    func clamped(to rate: TimecodeFrameRate) -> SMPTEComponents {
        SMPTEComponents(
            hours: max(0, min(23, hours)),
            minutes: max(0, min(59, minutes)),
            seconds: max(0, min(59, seconds)),
            frames: max(0, min(rate.countingFPS - 1, frames))
        )
    }

    func formatted(rate: TimecodeFrameRate) -> String {
        let c = clamped(to: rate)
        let sep = rate.frameSeparator
        return String(format: "%02d:%02d:%02d\(sep)%02d", c.hours, c.minutes, c.seconds, c.frames)
    }
}

enum SMPTETimecode {
    /// Parse `HH:MM:SS:FF` or drop-frame `HH:MM:SS;FF`.
    static func parse(_ raw: String, rate: TimecodeFrameRate) -> SMPTEComponents? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: ";", with: ":")
            .replacingOccurrences(of: ".", with: ":")
        let parts = normalized.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4,
              let h = Int(parts[0]),
              let m = Int(parts[1]),
              let s = Int(parts[2]),
              let f = Int(parts[3]),
              (0...23).contains(h),
              (0...59).contains(m),
              (0...59).contains(s),
              (0..<rate.countingFPS).contains(f)
        else { return nil }
        return SMPTEComponents(hours: h, minutes: m, seconds: s, frames: f)
    }

    /// Absolute frame index from TC numbers (handles drop-frame skipping).
    static func absoluteFrame(of tc: SMPTEComponents, rate: TimecodeFrameRate) -> Int {
        let c = tc.clamped(to: rate)
        if rate.isDropFrame {
            let totalMinutes = 60 * c.hours + c.minutes
            return ((totalMinutes * 60) + c.seconds) * 30 + c.frames
                - 2 * (totalMinutes - totalMinutes / 10)
        }
        let fps = rate.countingFPS
        return ((c.hours * 3600 + c.minutes * 60 + c.seconds) * fps) + c.frames
    }

    static func components(fromAbsolute absolute: Int, rate: TimecodeFrameRate) -> SMPTEComponents {
        let n = max(0, absolute)
        if rate.isDropFrame {
            return dropFrameComponents(fromAbsolute: n)
        }
        let fps = rate.countingFPS
        let frames = n % fps
        let totalSec = n / fps
        let seconds = totalSec % 60
        let totalMin = totalSec / 60
        let minutes = totalMin % 60
        let hours = (totalMin / 60) % 24
        return SMPTEComponents(hours: hours, minutes: minutes, seconds: seconds, frames: frames)
    }

    /// Timecode at a timeline display time (real seconds → frame number → TC label).
    static func components(fromDisplaySeconds seconds: TimeInterval, rate: TimecodeFrameRate) -> SMPTEComponents {
        let fps = rate.framesPerSecond
        let absolute = Int(floor(max(0, seconds) * fps + 1e-9))
        return components(fromAbsolute: absolute, rate: rate)
    }

    /// Real-time seconds for a timecode value at `rate` (DF-aware).
    static func realtimeSeconds(of tc: SMPTEComponents, rate: TimecodeFrameRate) -> TimeInterval {
        Double(absoluteFrame(of: tc, rate: rate)) / rate.framesPerSecond
    }

    // MARK: - Digit entry (HHMMSSFF, right-to-left)

    static let digitCount = 8

    static func digits(from tc: SMPTEComponents) -> String {
        let c = tc
        return String(format: "%02d%02d%02d%02d", c.hours, c.minutes, c.seconds, c.frames)
    }

    static func digits(fromDisplaySeconds seconds: TimeInterval, rate: TimecodeFrameRate) -> String {
        digits(from: components(fromDisplaySeconds: seconds, rate: rate))
    }

    static func format(fromDigits digits: String, rate: TimecodeFrameRate) -> String {
        components(fromDigits: digits, rate: rate).formatted(rate: rate)
    }

    static func components(fromDigits digits: String, rate: TimecodeFrameRate) -> SMPTEComponents {
        let padded = padDigits(digits)
        let h = Int(padded.prefix(2)) ?? 0
        let m = Int(padded.dropFirst(2).prefix(2)) ?? 0
        let s = Int(padded.dropFirst(4).prefix(2)) ?? 0
        let f = Int(padded.dropFirst(6).prefix(2)) ?? 0
        return SMPTEComponents(
            hours: min(23, h),
            minutes: min(59, m),
            seconds: min(59, s),
            frames: min(rate.countingFPS - 1, f)
        ).clamped(to: rate)
    }

    static func appendDigit(_ digits: String, _ digit: Character) -> String {
        guard digit.isNumber else { return digits }
        return String((digits + String(digit)).suffix(digitCount))
    }

    static func deleteDigit(_ digits: String) -> String {
        String(digits.dropLast())
    }

    private static func padDigits(_ digits: String) -> String {
        let filtered = digits.filter(\.isNumber)
        let clipped = String(filtered.suffix(digitCount))
        return String(repeating: "0", count: digitCount - clipped.count) + clipped
    }

    // MARK: - Ruler ticks (SMPTE boundaries)

    /// True when `absolute` is the first frame of a timecode second (including DF minute starts at ;02).
    static func isSecondBoundary(absolute: Int, rate: TimecodeFrameRate) -> Bool {
        guard absolute > 0 else { return true }
        let cur = components(fromAbsolute: absolute, rate: rate)
        let prev = components(fromAbsolute: absolute - 1, rate: rate)
        return cur.hours != prev.hours
            || cur.minutes != prev.minutes
            || cur.seconds != prev.seconds
    }

    /// Absolute frame of the first TC-second boundary at or after `absolute`.
    static func nextSecondBoundary(atOrAfter absolute: Int, rate: TimecodeFrameRate) -> Int {
        var a = max(0, absolute)
        let limit = a + rate.countingFPS + 2
        while a <= limit {
            if isSecondBoundary(absolute: a, rate: rate) { return a }
            a += 1
        }
        return max(0, absolute)
    }

    /// How many TC seconds between labeled major ticks, based on zoom.
    static func majorLabelStepSeconds(pixelsPerSecond: Double, rate: TimecodeFrameRate, targetPx: Double = 100) -> Int {
        let wallPerTCSecond = Double(rate.countingFPS) / rate.framesPerSecond
        let rawWall = targetPx / max(pixelsPerSecond, 1)
        let rawTC = rawWall / wallPerTCSecond
        let candidates = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600]
        return candidates.first { Double($0) >= rawTC } ?? 7200
    }

    /// Internal timeline times (0 = left edge) for labeled major ticks aligned to TC.
    static func majorTickInternalTimes(
        origin: TimeInterval,
        contentEnd: TimeInterval,
        rate: TimecodeFrameRate,
        pixelsPerSecond: Double
    ) -> [TimeInterval] {
        let stepSec = majorLabelStepSeconds(pixelsPerSecond: pixelsPerSecond, rate: rate)
        return tickInternalTimes(
            origin: origin,
            contentEnd: contentEnd,
            rate: rate,
            stepTCSeconds: stepSec,
            maxTicks: 2_000
        )
    }

    /// Internal times for minor ruler ticks (TC-aligned; step coarsens with zoom).
    static func minorTickInternalTimes(
        origin: TimeInterval,
        contentEnd: TimeInterval,
        rate: TimecodeFrameRate,
        pixelsPerSecond: Double
    ) -> [TimeInterval] {
        let majorStep = majorLabelStepSeconds(pixelsPerSecond: pixelsPerSecond, rate: rate)
        // Minor ticks denser than labels, but never denser than 1 TC second.
        let minorStep = max(1, majorStep / 5)
        return tickInternalTimes(
            origin: origin,
            contentEnd: contentEnd,
            rate: rate,
            stepTCSeconds: minorStep,
            maxTicks: 4_000
        )
    }

    /// Generate internal times at SMPTE second boundaries every `stepTCSeconds`.
    /// Advances by absolute-frame steps (cheap) after snapping the first boundary.
    private static func tickInternalTimes(
        origin: TimeInterval,
        contentEnd: TimeInterval,
        rate: TimecodeFrameRate,
        stepTCSeconds: Int,
        maxTicks: Int
    ) -> [TimeInterval] {
        let fps = rate.framesPerSecond
        guard fps > 0, contentEnd.isFinite, origin.isFinite, contentEnd >= 0 else { return [] }

        let endDisplay = origin + contentEnd
        guard endDisplay.isFinite else { return [] }

        // Cap absolute frame span so we never build enormous ranges.
        let originAbs = Int(floor(max(0, origin) * fps + 1e-9))
        let rawEndAbs = endDisplay * fps
        guard rawEndAbs.isFinite, rawEndAbs < Double(Int.max / 4) else { return [] }
        let endAbs = Int(ceil(max(0, rawEndAbs) + 1e-9))

        var frame = nextSecondBoundary(atOrAfter: originAbs, rate: rate)
        let startTC = components(fromAbsolute: frame, rate: rate)
        let totalSec = startTC.hours * 3600 + startTC.minutes * 60 + startTC.seconds
        let rem = totalSec % stepTCSeconds
        if rem != 0 {
            let skip = stepTCSeconds - rem
            frame = nextSecondBoundary(atOrAfter: frame + skip * rate.countingFPS, rate: rate)
        }

        let stepFrames = max(1, stepTCSeconds * rate.countingFPS)
        var times: [TimeInterval] = []
        times.reserveCapacity(min(maxTicks, max(1, (endAbs - frame) / stepFrames + 1)))

        var i = 0
        while frame <= endAbs, i < maxTicks {
            let wall = Double(frame) / fps
            let tInternal = wall - origin
            if tInternal >= -1e-6, tInternal <= contentEnd + 1e-6 {
                times.append(max(0, tInternal))
            }
            // Fast advance — NDF exact; DF stays on second starts when seeded from one.
            let next = frame + stepFrames
            if next <= frame { break }
            frame = next
            i += 1
        }
        return times
    }

    // MARK: - Drop-frame

    /// Convert a contiguous frame count to 29.97 drop-frame HH:MM:SS;FF.
    private static func dropFrameComponents(fromAbsolute frameNumber: Int) -> SMPTEComponents {
        // 10 minutes of DF video = 17982 frames (instead of 18000).
        let framesPer10Min = 17_982
        let d = frameNumber / framesPer10Min
        let m = frameNumber % framesPer10Min
        var adjusted = frameNumber + 18 * d
        if m >= 2 {
            adjusted += 2 * ((m - 2) / 1_798)
        }
        let frames = adjusted % 30
        let totalSec = adjusted / 30
        let seconds = totalSec % 60
        let totalMin = totalSec / 60
        let minutes = totalMin % 60
        let hours = (totalMin / 60) % 24
        return SMPTEComponents(hours: hours, minutes: minutes, seconds: seconds, frames: frames)
    }

    /// Pack one LTC frame into 80 bits (LSB-first within each BCD nibble group, per SMPTE 12M).
    static func ltcBits(for tc: SMPTEComponents, rate: TimecodeFrameRate) -> [Bool] {
        let c = tc.clamped(to: rate)
        var bits = [Bool](repeating: false, count: 80)

        func setBCD(unitsBit: Int, tensBit: Int, tensWidth: Int, value: Int) {
            let units = value % 10
            let tens = value / 10
            for i in 0..<4 {
                bits[unitsBit + i] = ((units >> i) & 1) == 1
            }
            for i in 0..<tensWidth {
                bits[tensBit + i] = ((tens >> i) & 1) == 1
            }
        }

        setBCD(unitsBit: 0, tensBit: 8, tensWidth: 2, value: c.frames)
        bits[10] = rate.isDropFrame // drop-frame flag
        bits[11] = false // color frame

        setBCD(unitsBit: 16, tensBit: 24, tensWidth: 3, value: c.seconds)
        setBCD(unitsBit: 32, tensBit: 40, tensWidth: 3, value: c.minutes)
        setBCD(unitsBit: 48, tensBit: 56, tensWidth: 2, value: c.hours)

        // Sync word (bits 64–79): 0011 1111 1111 1101
        let sync: [Bool] = [
            false, false, true, true,
            true, true, true, true,
            true, true, true, true,
            true, true, false, true
        ]
        for i in 0..<16 {
            bits[64 + i] = sync[i]
        }
        return bits
    }
}
