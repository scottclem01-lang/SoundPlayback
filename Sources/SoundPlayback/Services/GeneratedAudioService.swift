import AVFoundation
import Foundation

enum GeneratedAudioError: LocalizedError {
    case writeFailed
    case empty

    var errorDescription: String? {
        switch self {
        case .writeFailed: return "Could not write generated audio."
        case .empty: return "Generated audio was empty."
        }
    }
}

/// Synthesizes intro clicks / thump beds and writes them as WAV so sessions reload correctly.
enum GeneratedAudioService {
    private static let peakBuckets = 2048

    static func makeIntroClicks(
        tempoBPM: Double,
        clickCount: Int,
        sampleRate: Double
    ) throws -> ImportedAudio {
        let bpm = max(20, min(400, tempoBPM))
        let count = max(1, min(64, clickCount))
        let beat = 60.0 / bpm
        let clickLen = min(0.045, beat * 0.35)
        // Pad through the following beat so the clip ends where the next click would start.
        let totalDuration = beat * Double(count)
        let frameCount = max(1, Int((totalDuration * sampleRate).rounded(.up)))
        var samples = [Float](repeating: 0, count: frameCount)

        for i in 0..<count {
            let start = Int((Double(i) * beat * sampleRate).rounded())
            renderClick(into: &samples, start: start, length: clickLen, sampleRate: sampleRate)
        }

        return try wrap(
            samples: samples,
            sampleRate: sampleRate,
            basename: "intro-clicks-\(Int(bpm.rounded()))bpm-\(count)"
        )
    }

    static func makeThumpTrack(
        tempoBPM: Double,
        frequencyHz: Double,
        thumpTenths: Int,
        trackLengthSeconds: Double,
        sampleRate: Double
    ) throws -> ImportedAudio {
        let bpm = max(20, min(400, tempoBPM))
        let freq = max(20, min(4000, frequencyHz))
        let thumpDur = max(0.05, min(2.0, Double(max(1, thumpTenths)) / 10.0))
        let length = max(thumpDur, min(600, trackLengthSeconds))
        let beat = 60.0 / bpm
        let frameCount = max(1, Int((length * sampleRate).rounded(.up)))
        var samples = [Float](repeating: 0, count: frameCount)

        var t = 0.0
        while t < length - 0.001 {
            let start = Int((t * sampleRate).rounded())
            renderTonePulse(
                into: &samples,
                start: start,
                length: min(thumpDur, max(0, length - t)),
                frequency: freq,
                sampleRate: sampleRate
            )
            t += beat
        }

        return try wrap(
            samples: samples,
            sampleRate: sampleRate,
            basename: "thump-\(Int(bpm.rounded()))bpm-\(Int(freq.rounded()))hz"
        )
    }

    /// Linear Timecode (SMPTE 12M bi-phase mark) as a mono WAV.
    /// Frame boundaries are sample-accurate so LTC stays locked to wall-clock / timeline time.
    static func makeTimecode(
        frameRate: TimecodeFrameRate,
        start: SMPTEComponents,
        lengthSeconds: Double,
        sampleRate: Double
    ) throws -> ImportedAudio {
        let length = max(0.5, min(14_400, lengthSeconds))
        let fps = frameRate.framesPerSecond
        let ltcFrameCount = max(1, Int(ceil(length * fps - 1e-12)))
        // Exact sample span for N frames (avoids cumulative float drift).
        let frameCountAudio = max(1, Int((Double(ltcFrameCount) * sampleRate / fps).rounded(.up)))
        let startAbsolute = SMPTETimecode.absoluteFrame(of: start, rate: frameRate)

        var samples = [Float](repeating: 0, count: frameCountAudio)
        var level: Float = 0.85

        for frameIndex in 0..<ltcFrameCount {
            let frameStart = Int((Double(frameIndex) * sampleRate / fps).rounded(.down))
            let frameEnd = Int((Double(frameIndex + 1) * sampleRate / fps).rounded(.down))
            let frameSamples = max(1, frameEnd - frameStart)

            let tc = SMPTETimecode.components(
                fromAbsolute: startAbsolute + frameIndex,
                rate: frameRate
            )
            let bits = SMPTETimecode.ltcBits(for: tc, rate: frameRate)

            for (bitIndex, bit) in bits.enumerated() {
                let bitStart = frameStart + (bitIndex * frameSamples) / 80
                let bitEnd = frameStart + ((bitIndex + 1) * frameSamples) / 80
                let mid = bitStart + max(1, (bitEnd - bitStart) / 2)

                // Transition at bit start.
                level = -level
                fillSamples(&samples, from: bitStart, to: mid, level: level)
                if bit {
                    level = -level
                }
                fillSamples(&samples, from: mid, to: bitEnd, level: level)
            }
        }

        let rateTag = frameRate.rawValue.replacingOccurrences(of: " ", with: "")
        let startTag = start.formatted(rate: frameRate)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ";", with: "-")
        return try wrap(
            samples: samples,
            sampleRate: sampleRate,
            basename: "ltc-\(rateTag)-\(startTag)"
        )
    }

    // MARK: - Synthesis

    private static func fillSamples(
        _ samples: inout [Float],
        from start: Int,
        to end: Int,
        level: Float
    ) {
        let lo = max(0, start)
        let hi = min(samples.count, end)
        guard lo < hi else { return }
        for i in lo..<hi {
            samples[i] = level
        }
    }

    private static func renderClick(
        into samples: inout [Float],
        start: Int,
        length: TimeInterval,
        sampleRate: Double
    ) {
        let n = Int((length * sampleRate).rounded())
        guard n > 0 else { return }
        for i in 0..<n {
            let idx = start + i
            guard idx >= 0, idx < samples.count else { break }
            let t = Double(i) / sampleRate
            let env = exp(-t * 90)
            // Two partials for a sharp woodblock-ish tick.
            let tone = sin(2 * .pi * 1800 * t) * 0.55 + sin(2 * .pi * 3200 * t) * 0.35
            let noise = Float.random(in: -1...1) * 0.15
            samples[idx] += Float(tone) * Float(env) * 0.85 + noise * Float(env)
        }
    }

    /// Pure sine pulse at a fixed frequency — easy to notch out of dialogue later.
    private static func renderTonePulse(
        into samples: inout [Float],
        start: Int,
        length: TimeInterval,
        frequency: Double,
        sampleRate: Double
    ) {
        let n = Int((length * sampleRate).rounded())
        guard n > 0 else { return }
        let fade = min(0.01, length * 0.25)
        for i in 0..<n {
            let idx = start + i
            guard idx >= 0, idx < samples.count else { break }
            let t = Double(i) / sampleRate
            let remaining = length - t
            var env = 1.0
            if fade > 0 {
                if t < fade { env = t / fade }
                if remaining < fade { env = min(env, remaining / fade) }
            }
            samples[idx] += Float(sin(2 * .pi * frequency * t) * env * 0.55)
        }
    }

    // MARK: - Persist + wrap

    private static func wrap(
        samples: [Float],
        sampleRate: Double,
        basename: String
    ) throws -> ImportedAudio {
        guard !samples.isEmpty else { throw GeneratedAudioError.empty }
        let url = try writeWAV(samples: samples, sampleRate: sampleRate, basename: basename)
        let peaks = [makePeaks(samples: samples)]
        return ImportedAudio(
            url: url,
            sampleRate: sampleRate,
            channels: [samples],
            duration: Double(samples.count) / sampleRate,
            peaks: peaks
        )
    }

    private static func generatedDirectory() throws -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SoundPlayback", isDirectory: true)
            .appendingPathComponent("Generated", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func writeWAV(
        samples: [Float],
        sampleRate: Double,
        basename: String
    ) throws -> URL {
        let dir = try generatedDirectory()
        let url = dir.appendingPathComponent("\(basename)-\(UUID().uuidString).wav")

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { throw GeneratedAudioError.writeFailed }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw GeneratedAudioError.writeFailed
        }
        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { src in
            if let dst = buffer.floatChannelData?[0], let base = src.baseAddress {
                dst.update(from: base, count: samples.count)
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private static func makePeaks(samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let count = min(peakBuckets, samples.count)
        var peaks = [Float](repeating: 0, count: count)
        let step = Double(samples.count) / Double(count)
        for i in 0..<count {
            let start = Int(Double(i) * step)
            let end = min(samples.count, Int(Double(i + 1) * step))
            var maxVal: Float = 0
            if start < end {
                for s in start..<end {
                    maxVal = max(maxVal, abs(samples[s]))
                }
            }
            peaks[i] = maxVal
        }
        return peaks
    }
}
