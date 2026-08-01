import AVFoundation
import Foundation

struct ImportedAudio: Sendable {
    let url: URL
    let sampleRate: Double
    /// Planar mono channels (stereo → two arrays).
    let channels: [[Float]]
    let duration: TimeInterval
    /// Display peaks per channel (~pixels-worth of max abs values).
    let peaks: [[Float]]

    var channelCount: Int { channels.count }
}

enum AudioImportError: LocalizedError {
    case cannotOpen
    case noAudioData
    case convertFailed

    var errorDescription: String? {
        switch self {
        case .cannotOpen: return "Could not open audio file."
        case .noAudioData: return "Audio file contained no samples."
        case .convertFailed: return "Could not convert audio to playback format."
        }
    }
}

enum AudioFileImporter {
    private static let peakBucketCount = 2048

    /// Fast channel-count probe without decoding samples.
    static func channelCount(at url: URL) throws -> Int {
        let file = try AVAudioFile(forReading: url)
        return Int(file.processingFormat.channelCount)
    }

    static func importFile(at url: URL, targetSampleRate: Double) throws -> ImportedAudio {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { throw AudioImportError.noAudioData }

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw AudioImportError.cannotOpen
        }
        try file.read(into: sourceBuffer)
        sourceBuffer.frameLength = frameCount

        let channelCount = Int(sourceFormat.channelCount)
        var planar: [[Float]] = []

        if abs(sourceFormat.sampleRate - targetSampleRate) < 0.5 {
            planar = extractPlanar(from: sourceBuffer, channelCount: channelCount)
        } else {
            planar = try convertPlanar(
                buffer: sourceBuffer,
                sourceFormat: sourceFormat,
                targetSampleRate: targetSampleRate,
                channelCount: channelCount
            )
        }

        guard let first = planar.first, !first.isEmpty else { throw AudioImportError.noAudioData }
        let duration = Double(first.count) / targetSampleRate
        let peaks = planar.map { makePeaks(samples: $0, buckets: peakBucketCount) }

        return ImportedAudio(
            url: url,
            sampleRate: targetSampleRate,
            channels: planar,
            duration: duration,
            peaks: peaks
        )
    }

    private static func extractPlanar(from buffer: AVAudioPCMBuffer, channelCount: Int) -> [[Float]] {
        guard let data = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        var result: [[Float]] = []
        for ch in 0..<channelCount {
            let ptr = data[ch]
            result.append(Array(UnsafeBufferPointer(start: ptr, count: frames)))
        }
        return result
    }

    private static func convertPlanar(
        buffer: AVAudioPCMBuffer,
        sourceFormat: AVAudioFormat,
        targetSampleRate: Double,
        channelCount: Int
    ) throws -> [[Float]] {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        ) else { throw AudioImportError.convertFailed }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioImportError.convertFailed
        }

        let ratio = targetSampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw AudioImportError.convertFailed
        }

        var error: NSError?
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        if let error { throw error }

        return extractPlanar(from: outBuffer, channelCount: channelCount)
    }

    private static func makePeaks(samples: [Float], buckets: Int) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let count = min(buckets, samples.count)
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
