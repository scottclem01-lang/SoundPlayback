import SwiftUI

struct EditGeneratedClipSheet: View {
    let request: EditGeneratedClipRequest
    /// Project timeline frame rate (locked LTC uses this).
    var projectFrameRate: TimecodeFrameRate = .fps24
    /// Timeline display seconds at the clip’s left edge (for lock-to-timeline).
    var lockedDisplaySeconds: TimeInterval = 0
    let onCancel: () -> Void
    let onConfirm: (EditGeneratedClipRequest) -> Void

    @State private var tempoBPM: Double = 120
    @State private var clickCount: Int = 4
    @State private var frequencyHz: Double = 55
    @State private var thumpTenths: Int = 2
    @State private var trackLengthSeconds: Double = 16
    @State private var frameRate: TimecodeFrameRate = .fps24
    @State private var startTimecode: String = "00:00:00:00"
    @State private var lockToTimeline = true
    @State private var startError: String?

    private var effectiveRate: TimecodeFrameRate {
        lockToTimeline ? projectFrameRate : frameRate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit \(request.title)")
                .font(.headline)

            Text("Changes regenerate this clip in place on the timeline.")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch request.kind {
            case .introClicks:
                tempoRow
                HStack {
                    Text("Number of clicks")
                    Spacer()
                    Stepper(value: $clickCount, in: 1...32) {
                        Text("\(clickCount)")
                            .frame(width: 28, alignment: .trailing)
                    }
                }

            case .thump:
                tempoRow
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

                lengthRow

            case .timecode:
                Toggle("Lock to timeline", isOn: $lockToTimeline)
                    .toggleStyle(.checkbox)
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

                lengthRow
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    var updated = request
                    updated.tempoBPM = tempoBPM
                    updated.clickCount = clickCount
                    updated.frequencyHz = frequencyHz
                    updated.thumpTenths = thumpTenths
                    updated.trackLengthSeconds = trackLengthSeconds
                    updated.lockToTimeline = lockToTimeline
                    if request.kind == .timecode {
                        let rate = effectiveRate
                        if lockToTimeline { refreshLockedStart() }
                        guard SMPTETimecode.parse(startTimecode, rate: rate) != nil else {
                            startError = "Enter start as \(rate.isDropFrame ? "HH:MM:SS;FF" : "HH:MM:SS:FF")"
                            return
                        }
                        startError = nil
                        updated.timecodeFrameRate = rate
                        updated.timecodeStart = startTimecode
                    }
                    onConfirm(updated)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: sheetWidth)
        .onAppear {
            tempoBPM = request.tempoBPM
            clickCount = request.clickCount
            frequencyHz = request.frequencyHz
            thumpTenths = request.thumpTenths
            trackLengthSeconds = request.trackLengthSeconds
            frameRate = request.timecodeFrameRate
            startTimecode = request.timecodeStart
            lockToTimeline = request.lockToTimeline
            if request.kind == .timecode, lockToTimeline {
                frameRate = projectFrameRate
                refreshLockedStart()
            }
        }
    }

    private var sheetWidth: CGFloat {
        switch request.kind {
        case .thump, .timecode: return 420
        case .introClicks: return 360
        }
    }

    private var tempoRow: some View {
        HStack {
            Text("Tempo (BPM)")
            Spacer()
            TextField("", value: $tempoBPM, format: .number.precision(.fractionLength(0...1)))
                .frame(width: 72)
                .multilineTextAlignment(.trailing)
        }
    }

    private var lengthRow: some View {
        HStack {
            Text(request.kind == .timecode ? "Length (seconds)" : "Track length (seconds)")
            Spacer()
            TextField("", value: $trackLengthSeconds, format: .number.precision(.fractionLength(0...1)))
                .frame(width: 72)
                .multilineTextAlignment(.trailing)
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
