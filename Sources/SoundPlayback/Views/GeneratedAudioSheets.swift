import SwiftUI

struct IntroClicksSheet: View {
    let trackCount: Int
    var initialTempoBPM: Double = 120
    let onCancel: () -> Void
    let onConfirm: (IntroClicksRequest) -> Void

    @State private var tempoBPM: Double = 120
    @State private var clickCount: Int = 4
    @State private var selectedTrack: Int = -1 // -1 = new

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Intro Clicks")
                .font(.headline)

            Text("Places metronome clicks on the chosen track starting at the play marker.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Tempo (BPM)")
                Spacer()
                TextField("", value: $tempoBPM, format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Number of clicks")
                Spacer()
                Stepper(value: $clickCount, in: 1...32) {
                    Text("\(clickCount)")
                        .frame(width: 28, alignment: .trailing)
                }
            }

            Picker("Track", selection: $selectedTrack) {
                ForEach(0..<max(trackCount, 0), id: \.self) { index in
                    Text("Track \(index + 1)").tag(index)
                }
                Text("New track").tag(-1)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    var request = IntroClicksRequest()
                    request.tempoBPM = tempoBPM
                    request.clickCount = clickCount
                    request.track = selectedTrack < 0 ? .newTrack : .existing(selectedTrack)
                    onConfirm(request)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            selectedTrack = -1
            tempoBPM = initialTempoBPM
        }
    }
}

struct ThumpTrackSheet: View {
    let trackCount: Int
    var initialTempoBPM: Double = 120
    let onCancel: () -> Void
    let onConfirm: (ThumpTrackRequest) -> Void

    @State private var tempoBPM: Double = 120
    @State private var frequencyHz: Double = 55
    @State private var thumpTenths: Int = 2
    @State private var trackLengthSeconds: Double = 16
    @State private var selectedTrack: Int = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Thump Track")
                .font(.headline)

            Text("Places a pure sine tone on each beat at the play marker — easy to notch out of dialogue later.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Tempo (BPM)")
                Spacer()
                TextField("", value: $tempoBPM, format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Frequency (Hz)")
                Spacer()
                TextField("", value: $frequencyHz, format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Tone length (tenths of a second)")
                Spacer()
                Stepper(value: $thumpTenths, in: 1...20) {
                    Text("\(thumpTenths)")
                        .frame(width: 28, alignment: .trailing)
                }
            }

            HStack {
                Text("Track length (seconds)")
                Spacer()
                TextField("", value: $trackLengthSeconds, format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
            }

            Picker("Track", selection: $selectedTrack) {
                ForEach(0..<max(trackCount, 0), id: \.self) { index in
                    Text("Track \(index + 1)").tag(index)
                }
                Text("New track").tag(-1)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    var request = ThumpTrackRequest()
                    request.tempoBPM = tempoBPM
                    request.frequencyHz = frequencyHz
                    request.thumpTenths = thumpTenths
                    request.trackLengthSeconds = trackLengthSeconds
                    request.track = selectedTrack < 0 ? .newTrack : .existing(selectedTrack)
                    onConfirm(request)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            selectedTrack = -1
            tempoBPM = initialTempoBPM
        }
    }
}

struct TimecodeTrackSheet: View {
    let trackCount: Int
    /// Project timeline frame rate (locked LTC always uses this).
    var projectFrameRate: TimecodeFrameRate = .fps24
    /// Suggested start when lock-to-timeline is on (display seconds).
    var lockedDisplaySeconds: TimeInterval = 0
    let onCancel: () -> Void
    let onConfirm: (TimecodeTrackRequest) -> Void

    @State private var frameRate: TimecodeFrameRate = .fps24
    @State private var startTimecode: String = "00:00:00:00"
    @State private var lengthSeconds: Double = 60
    @State private var lockToTimeline = true
    @State private var selectedTrack: Int = -1
    @State private var startError: String?

    private var effectiveRate: TimecodeFrameRate {
        lockToTimeline ? projectFrameRate : frameRate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate Timecode")
                .font(.headline)

            Text("Creates SMPTE Linear Timecode (LTC) audio. Locked clips match the project timeline frame rate and clock.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Lock to timeline", isOn: $lockToTimeline)
                .toggleStyle(.checkbox)
                .help("LTC at the clip start matches the timeline clock. Uses the project FPS dropdown.")
                .onChange(of: lockToTimeline) { _, locked in
                    if locked {
                        frameRate = projectFrameRate
                        refreshLockedStart()
                    }
                }

            if lockToTimeline {
                HStack {
                    Text("Frame rate")
                    Spacer()
                    Text(projectFrameRate.displayName)
                        .foregroundStyle(SPTheme.textSecondary)
                        .help("Change this with the FPS control on the transport bar")
                }
            } else {
                Picker("Frame rate", selection: $frameRate) {
                    ForEach(TimecodeFrameRate.allCases) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .onChange(of: frameRate) { _, _ in
                    if let tc = SMPTETimecode.parse(startTimecode, rate: frameRate) {
                        startTimecode = tc.formatted(rate: frameRate)
                    }
                }
            }

            HStack {
                Text("Start time")
                Spacer()
                TextField(
                    effectiveRate.isDropFrame ? "HH:MM:SS;FF" : "HH:MM:SS:FF",
                    text: $startTimecode
                )
                .frame(width: 110)
                .multilineTextAlignment(.trailing)
                .disabled(lockToTimeline)
                .foregroundStyle(lockToTimeline ? SPTheme.textSecondary : SPTheme.textPrimary)
            }

            if let startError {
                Text(startError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("Length (seconds)")
                Spacer()
                TextField("", value: $lengthSeconds, format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
            }

            Picker("Track", selection: $selectedTrack) {
                ForEach(0..<max(trackCount, 0), id: \.self) { index in
                    Text("Track \(index + 1)").tag(index)
                }
                Text("New track").tag(-1)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    if lockToTimeline {
                        refreshLockedStart()
                    }
                    let rate = effectiveRate
                    guard SMPTETimecode.parse(startTimecode, rate: rate) != nil else {
                        startError = "Enter start as \(rate.isDropFrame ? "HH:MM:SS;FF" : "HH:MM:SS:FF")"
                        return
                    }
                    startError = nil
                    var request = TimecodeTrackRequest()
                    request.frameRate = rate
                    request.startTimecode = startTimecode
                    request.lengthSeconds = lengthSeconds
                    request.lockToTimeline = lockToTimeline
                    request.track = selectedTrack < 0 ? .newTrack : .existing(selectedTrack)
                    onConfirm(request)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            selectedTrack = -1
            frameRate = projectFrameRate
            refreshLockedStart()
        }
    }

    private func refreshLockedStart() {
        let tc = SMPTETimecode.components(
            fromDisplaySeconds: lockedDisplaySeconds,
            rate: projectFrameRate
        )
        startTimecode = tc.formatted(rate: projectFrameRate)
    }
}
