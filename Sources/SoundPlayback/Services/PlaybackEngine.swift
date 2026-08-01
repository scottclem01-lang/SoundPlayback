import AVFoundation
import CoreAudio
import Foundation

enum TransportState: Equatable {
    case stopped
    case playing
    case paused
}

/// Shared playable snapshot for the realtime render callback.
final class MixerRenderState: @unchecked Sendable {
    struct ClipVoice {
        let samples: [Float]
        let sampleRate: Double
        let timelineStart: TimeInterval
        let sourceIn: TimeInterval
        let duration: TimeInterval
    }

    struct TrackVoice {
        var volume: Float
        var isMuted: Bool
        var isSoloed: Bool
        var outputMask: Int
        var clips: [ClipVoice]
    }

    let lock = NSLock()
    var tracks: [TrackVoice] = []
    var isPlaying = false
    var playheadSeconds: Double = 0
    var sampleRate: Double = 48_000
    var outputChannelCount: Int = 2
    /// Incremented on every seek so in-flight render callbacks don't clobber the new playhead.
    var seekGeneration: UInt64 = 0
    /// Peak hold per output channel (updated in render, read/decayed on main).
    var peakHold: [Float] = [0, 0, 0, 0]

    func sample(at time: TimeInterval, from clip: ClipVoice) -> Float {
        let local = time - clip.timelineStart
        guard local >= 0, local < clip.duration else { return 0 }
        let sourceTime = clip.sourceIn + local
        let pos = sourceTime * clip.sampleRate
        let i = Int(pos)
        guard i >= 0, i < clip.samples.count else { return 0 }
        let frac = Float(pos - Double(i))
        let a = clip.samples[i]
        let b = (i + 1 < clip.samples.count) ? clip.samples[i + 1] : a
        return a + (b - a) * frac
    }
}

@MainActor
final class PlaybackEngine: ObservableObject {
    @Published private(set) var transport: TransportState = .stopped
    @Published var playheadTime: TimeInterval = 0
    /// Meter levels 0…1 for up to 4 output channels.
    @Published private(set) var meterLevels: [Float] = [0, 0, 0, 0]

    private(set) var playStartTime: TimeInterval = 0

    private let audioEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let renderState = MixerRenderState()
    private var playheadTimer: Timer?
    private var isConfigured = false
    private var displayedMeters: [Float] = [0, 0, 0, 0]

    func setPlayStart(_ time: TimeInterval) {
        playStartTime = max(0, time)
        if transport != .playing {
            seekPlayhead(to: playStartTime)
        }
    }

    /// Seek playhead (and optionally play-start). Safe during playback — won't be overwritten by the current render buffer.
    func seekPlayhead(to time: TimeInterval, alsoSetPlayStart: Bool = false) {
        let t = max(0, time)
        if alsoSetPlayStart {
            playStartTime = t
        }
        playheadTime = t
        renderState.lock.lock()
        renderState.playheadSeconds = t
        renderState.seekGeneration &+= 1
        renderState.lock.unlock()
    }

    func scrubPlayhead(to time: TimeInterval) {
        seekPlayhead(to: time)
    }

    func configureOutput(deviceUID: String?, preferredSampleRate: Double) throws {
        let wasPlaying = transport == .playing
        if wasPlaying {
            renderState.lock.lock()
            renderState.isPlaying = false
            renderState.lock.unlock()
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        teardownNode()

        if let deviceUID, let deviceID = AudioDeviceService.deviceID(forUID: deviceUID) {
            try setCurrentDevice(deviceID)
        }

        audioEngine.prepare()

        let outFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        let engineSampleRate = outFormat.sampleRate > 0 ? outFormat.sampleRate : preferredSampleRate
        let engineChannelCount = max(1, min(4, Int(outFormat.channelCount)))

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: engineSampleRate,
            channels: AVAudioChannelCount(engineChannelCount),
            interleaved: false
        ) else {
            throw NSError(domain: "SoundPlayback", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not create audio format."
            ])
        }

        renderState.lock.lock()
        renderState.sampleRate = engineSampleRate
        renderState.outputChannelCount = engineChannelCount
        renderState.lock.unlock()

        let state = renderState
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, ablPointer -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(ablPointer)
            for buffer in abl {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }

            state.lock.lock()
            let playing = state.isPlaying
            var time = state.playheadSeconds
            let sr = state.sampleRate
            let tracks = state.tracks
            let outCount = state.outputChannelCount
            let seekGen = state.seekGeneration
            state.lock.unlock()

            guard playing, sr > 0 else { return noErr }

            let dt = 1.0 / sr
            let frames = Int(frameCount)
            var bufferPeaks = [Float](repeating: 0, count: max(outCount, 1))

            for frame in 0..<frames {
                var outs = [Float](repeating: 0, count: outCount)

                for track in tracks {
                    if track.isMuted { continue }

                    var sample: Float = 0
                    for clip in track.clips {
                        sample += state.sample(at: time, from: clip)
                    }
                    sample *= track.volume

                    for ch in 0..<outCount {
                        if track.outputMask & (1 << ch) != 0 {
                            outs[ch] += sample
                        }
                    }
                }

                if abl.count == 1, let data = abl[0].mData {
                    let channels = Int(abl[0].mNumberChannels)
                    let ptr = data.assumingMemoryBound(to: Float.self)
                    for ch in 0..<min(channels, outCount) {
                        let s = max(-1 as Float, min(1, outs[ch]))
                        ptr[frame * channels + ch] = s
                        bufferPeaks[ch] = max(bufferPeaks[ch], abs(s))
                    }
                } else {
                    for ch in 0..<min(abl.count, outCount) {
                        if let data = abl[ch].mData {
                            let ptr = data.assumingMemoryBound(to: Float.self)
                            let s = max(-1 as Float, min(1, outs[ch]))
                            ptr[frame] = s
                            bufferPeaks[ch] = max(bufferPeaks[ch], abs(s))
                        }
                    }
                }
                time += dt
            }

            state.lock.lock()
            if state.isPlaying, state.seekGeneration == seekGen {
                state.playheadSeconds = time
            }
            for ch in 0..<min(4, bufferPeaks.count) {
                state.peakHold[ch] = max(state.peakHold[ch], bufferPeaks[ch])
            }
            state.lock.unlock()
            return noErr
        }

        sourceNode = node
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.outputNode, format: format)
        try audioEngine.start()
        isConfigured = true

        if wasPlaying {
            renderState.lock.lock()
            renderState.isPlaying = true
            renderState.lock.unlock()
            transport = .playing
            startPlayheadTimer()
        }
    }

    func updateMix(session: PlaybackSession, buffers: [URL: ImportedAudio]) {
        var voices: [MixerRenderState.TrackVoice] = []
        for track in session.tracks {
            let clips: [MixerRenderState.ClipVoice] = track.clips.compactMap { clip in
                guard let imported = buffers[clip.sourceURL],
                      clip.sourceChannel >= 0,
                      clip.sourceChannel < imported.channels.count else { return nil }
                return MixerRenderState.ClipVoice(
                    samples: imported.channels[clip.sourceChannel],
                    sampleRate: imported.sampleRate,
                    timelineStart: clip.timelineStart,
                    sourceIn: clip.sourceIn,
                    duration: clip.duration
                )
            }
            voices.append(
                MixerRenderState.TrackVoice(
                    volume: Float(track.volume),
                    isMuted: track.isMuted,
                    isSoloed: track.isSoloed,
                    outputMask: track.outputMask.rawValue,
                    clips: clips
                )
            )
        }

        renderState.lock.lock()
        renderState.tracks = voices
        renderState.lock.unlock()
    }

    func play() {
        if !isConfigured {
            return
        }
        renderState.lock.lock()
        if transport == .stopped {
            renderState.playheadSeconds = playStartTime
            playheadTime = playStartTime
        }
        renderState.isPlaying = true
        renderState.lock.unlock()
        transport = .playing
        startPlayheadTimer()

        if !audioEngine.isRunning {
            try? audioEngine.start()
        }
    }

    func stop() {
        renderState.lock.lock()
        renderState.isPlaying = false
        renderState.playheadSeconds = playStartTime
        renderState.seekGeneration &+= 1
        for i in renderState.peakHold.indices { renderState.peakHold[i] = 0 }
        renderState.lock.unlock()
        transport = .stopped
        playheadTime = playStartTime
        displayedMeters = [0, 0, 0, 0]
        meterLevels = [0, 0, 0, 0]
        stopPlayheadTimer()
    }

    func pause() {
        renderState.lock.lock()
        renderState.isPlaying = false
        playheadTime = renderState.playheadSeconds
        renderState.lock.unlock()
        transport = .paused
        stopPlayheadTimer()
    }

    func togglePlayStop() {
        if transport == .playing {
            stop()
        } else {
            play()
        }
    }

    // MARK: - Private

    private func teardownNode() {
        if let sourceNode {
            audioEngine.disconnectNodeOutput(sourceNode)
            audioEngine.detach(sourceNode)
            self.sourceNode = nil
        }
        isConfigured = false
    }

    private func setCurrentDevice(_ deviceID: AudioDeviceID) throws {
        guard let audioUnit = audioEngine.outputNode.audioUnit else { return }
        var id = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Could not set output device (OSStatus \(status))."
            ])
        }
    }

    private func startPlayheadTimer() {
        stopPlayheadTimer()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pullPlayhead()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playheadTimer = timer
    }

    private func stopPlayheadTimer() {
        playheadTimer?.invalidate()
        playheadTimer = nil
    }

    private func pullPlayhead() {
        renderState.lock.lock()
        let t = renderState.playheadSeconds
        var peaks = renderState.peakHold
        // Decay / clear hold so next buffers rebuild peaks.
        for i in renderState.peakHold.indices {
            renderState.peakHold[i] *= 0.35
        }
        let channelCount = renderState.outputChannelCount
        let playing = renderState.isPlaying
        renderState.lock.unlock()

        playheadTime = t

        if !playing {
            peaks = [0, 0, 0, 0]
            displayedMeters = peaks
        } else {
            for i in 0..<4 {
                let target = i < peaks.count ? peaks[i] : 0
                // Smooth meter ballistics.
                if target > displayedMeters[i] {
                    displayedMeters[i] = target
                } else {
                    displayedMeters[i] = displayedMeters[i] * 0.82 + target * 0.18
                }
            }
        }
        var levels = displayedMeters
        while levels.count < 4 { levels.append(0) }
        // Zero unused channels beyond hardware count.
        for i in channelCount..<4 { levels[i] = 0 }
        meterLevels = Array(levels.prefix(4))
    }
}
