import SwiftUI

struct TransportBar: View {
    @ObservedObject var viewModel: SessionViewModel
    @ObservedObject var engine: PlaybackEngine

    var body: some View {
        HStack(spacing: 14) {
            Text(documentTitle)
                .font(.headline)
                .foregroundStyle(SPTheme.textPrimary)
                .lineLimit(1)
                .help(viewModel.documentURL?.path ?? "Unsaved session")

            if viewModel.isDirty {
                Text("•")
                .font(.headline)
                .foregroundStyle(SPTheme.accent)
                .help("Unsaved changes")
            }

            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SPTheme.accent)
                    .transition(.opacity)
            }

            Divider().frame(height: 18)

            Picker("Output", selection: deviceBinding) {
                Text("No output devices").tag(String?.none)
                ForEach(viewModel.outputDevices) { device in
                    Text("\(device.name) (\(device.outputChannelCount) ch)")
                        .tag(String?.some(device.uid))
                }
            }
            .frame(maxWidth: 240)
            .onTapGesture { viewModel.refreshDevices() }

            Toggle("Actively scroll", isOn: $viewModel.activelyScroll)
                .toggleStyle(.checkbox)
                .help("Keep the playhead centered while playing. Off = page jump when it leaves the view.")

            Toggle(
                "Marks are sequential",
                isOn: Binding(
                    get: { viewModel.marksAreSequential },
                    set: { viewModel.setMarksAreSequential($0) }
                )
            )
            .toggleStyle(.checkbox)
            .help("When on, marker numbers always match left-to-right order on the timeline.")

            Toggle("Snap", isOn: $viewModel.snapEnabled)
                .toggleStyle(.checkbox)
                .help("Snap dragged/trimmed clip edges to nearby clip starts, ends, and markers.")

            LevelMeterView(
                levels: engine.meterLevels,
                channelCount: viewModel.availableOutputCount
            )

            Spacer()

            Button("Undo") { viewModel.undoClipEdit() }
                .disabled(!viewModel.canUndo)

            HStack(spacing: 8) {
                Button("Stop") { viewModel.stop() }
                Button(engine.transport == .playing ? "Pause" : "Play") {
                    if engine.transport == .playing {
                        viewModel.pause()
                    } else {
                        viewModel.play()
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

    private var documentTitle: String {
        viewModel.documentDisplayName
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
