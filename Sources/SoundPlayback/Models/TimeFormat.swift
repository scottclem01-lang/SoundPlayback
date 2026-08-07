import Foundation

enum TimeFormat {
    /// SMPTE timeline / transport clock at the project frame rate.
    static func timecode(_ t: TimeInterval, rate: TimecodeFrameRate) -> String {
        SMPTETimecode.components(fromDisplaySeconds: t, rate: rate).formatted(rate: rate)
    }

    /// Transport / ruler clock. Uses `H:MM:SS.ff` when ≥ 1 hour, otherwise `MM:SS.ff`.
    /// Prefer `timecode(_:rate:)` for the timeline UI.
    static func clock(_ t: TimeInterval) -> String {
        let clamped = max(0, t)
        let totalCs = Int((clamped * 100).rounded(.down))
        let f = totalCs % 100
        let totalSec = totalCs / 100
        let s = totalSec % 60
        let totalMin = totalSec / 60
        let m = totalMin % 60
        let h = totalMin / 60
        if h > 0 {
            return String(format: "%d:%02d:%02d.%02d", h, m, s, f)
        }
        return String(format: "%02d:%02d.%02d", m, s, f)
    }

    /// Timeline-start display: fixed `HH:MM:SS.00` (centiseconds locked at 00).
    static func clockWithHours(_ t: TimeInterval) -> String {
        formatTimelineStart(fromDigits: digits(fromTime: t))
    }

    // MARK: - Right-to-left HH:MM:SS.00 digit entry (centiseconds always .00)

    static let timelineStartDigitCount = 6

    /// Whole-second HHMMSS digits for `t` (max 99:59:59).
    static func digits(fromTime t: TimeInterval) -> String {
        let totalSec = min(99 * 3600 + 59 * 60 + 59, Int(max(0, t)))
        let s = totalSec % 60
        let totalMin = totalSec / 60
        let m = totalMin % 60
        let h = totalMin / 60
        return String(format: "%02d%02d%02d", h, m, s)
    }

    /// `digits` are the typed HHMMSS characters (right-aligned, max 6).
    static func formatTimelineStart(fromDigits digits: String) -> String {
        let padded = padDigits(digits)
        let hh = padded.prefix(2)
        let mm = padded.dropFirst(2).prefix(2)
        let ss = padded.dropFirst(4).prefix(2)
        return "\(hh):\(mm):\(ss).00"
    }

    static func time(fromDigits digits: String) -> TimeInterval {
        let padded = padDigits(digits)
        let h = Int(padded.prefix(2)) ?? 0
        let m = Int(padded.dropFirst(2).prefix(2)) ?? 0
        let s = Int(padded.dropFirst(4).prefix(2)) ?? 0
        let minutes = min(59, m)
        let seconds = min(59, s)
        return TimeInterval(h * 3600 + minutes * 60 + seconds)
    }

    /// Append a digit from the right (shift-left entry). Keeps at most 6 digits.
    static func appendTimelineDigit(_ digits: String, _ digit: Character) -> String {
        guard digit.isNumber else { return digits }
        return String((digits + String(digit)).suffix(timelineStartDigitCount))
    }

    static func deleteTimelineDigit(_ digits: String) -> String {
        String(digits.dropLast())
    }

    private static func padDigits(_ digits: String) -> String {
        let filtered = digits.filter(\.isNumber)
        let clipped = String(filtered.suffix(timelineStartDigitCount))
        return String(repeating: "0", count: timelineStartDigitCount - clipped.count) + clipped
    }

    /// Parse `H:MM:SS.ff`, `MM:SS.ff`, `M:SS`, or plain seconds (`12.5`).
    static func parse(_ raw: String) -> TimeInterval? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            if parts.count == 3 {
                guard let hours = Double(parts[0]),
                      let minutes = Double(parts[1]),
                      let seconds = Double(parts[2]),
                      hours >= 0, minutes >= 0, seconds >= 0
                else { return nil }
                return hours * 3600 + minutes * 60 + seconds
            }
            if parts.count == 2 {
                guard let minutes = Double(parts[0]),
                      let seconds = Double(parts[1]),
                      minutes >= 0, seconds >= 0
                else { return nil }
                return minutes * 60 + seconds
            }
            return nil
        }

        return Double(trimmed).map { max(0, $0) }
    }

    /// Nice major tick spacing so labels stay ~`targetPx` apart.
    static func majorTickStep(pixelsPerSecond: Double, targetPx: Double = 80) -> TimeInterval {
        let raw = max(0.01, targetPx / max(pixelsPerSecond, 1))
        let candidates: [TimeInterval] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        return candidates.first { $0 >= raw } ?? 1200
    }
}
