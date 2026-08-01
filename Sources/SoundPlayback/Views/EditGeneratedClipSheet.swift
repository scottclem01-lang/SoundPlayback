import SwiftUI

struct EditGeneratedClipSheet: View {
    let request: EditGeneratedClipRequest
    let onCancel: () -> Void
    let onConfirm: (EditGeneratedClipRequest) -> Void

    @State private var tempoBPM: Double = 120
    @State private var clickCount: Int = 4
    @State private var frequencyHz: Double = 55
    @State private var thumpTenths: Int = 2
    @State private var trackLengthSeconds: Double = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit \(request.title)")
                .font(.headline)

            Text("Changes regenerate this clip in place on the timeline.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Tempo (BPM)")
                Spacer()
                TextField("", value: $tempoBPM, format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
            }

            switch request.kind {
            case .introClicks:
                HStack {
                    Text("Number of clicks")
                    Spacer()
                    Stepper(value: $clickCount, in: 1...32) {
                        Text("\(clickCount)")
                            .frame(width: 28, alignment: .trailing)
                    }
                }

            case .thump:
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
                    onConfirm(updated)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: request.kind == .thump ? 400 : 360)
        .onAppear {
            tempoBPM = request.tempoBPM
            clickCount = request.clickCount
            frequencyHz = request.frequencyHz
            thumpTenths = request.thumpTenths
            trackLengthSeconds = request.trackLengthSeconds
        }
    }
}
