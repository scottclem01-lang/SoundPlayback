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
