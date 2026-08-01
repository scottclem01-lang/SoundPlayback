import SwiftUI

struct TransportBar: View {
    @ObservedObject var viewModel: SessionViewModel
    @ObservedObject var engine: PlaybackEngine

    var body: some View {
        HStack(spacing: 14) {
            Text("SoundPlayback")
                .font(.headline)
                .foregroundStyle(SPTheme.textPrimary)

            Divider().frame(height: 18)

            Picker("Output", selection: deviceBinding) {
                Text("No output devices").tag(String?.none)
                ForEach(viewModel.outputDevices) { device in
                    Text("\(device.name) (\(device.outputChannelCount) ch)")
                        .tag(String?.some(device.uid))
                }
            }
            .frame(maxWidth: 320)
            .onTapGesture { viewModel.refreshDevices() }

            Spacer()

            HStack(spacing: 8) {
                Button("Stop") { engine.stop() }
                Button(engine.transport == .playing ? "Pause" : "Play") {
                    if engine.transport == .playing {
                        engine.pause()
                    } else {
                        engine.play()
                    }
                }
            }

            Text(timeString(engine.playheadTime))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(SPTheme.textSecondary)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SPTheme.panel)
    }

    private var deviceBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedDeviceUID },
            set: { viewModel.selectDevice($0) }
        )
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t)
        let m = total / 60
        let s = total % 60
        let f = Int((t - Double(total)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, f)
    }
}
