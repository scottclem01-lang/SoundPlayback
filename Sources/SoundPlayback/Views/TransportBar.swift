import SwiftUI

struct TransportBar: View {
    @ObservedObject var viewModel: SessionViewModel
    @ObservedObject var engine: PlaybackEngine

    @State private var isEditingTimelineStart = false
    /// Typed HHMMSS digits (right-to-left entry). Centiseconds always display as .00.
    @State private var timelineStartDigits = ""
    @FocusState private var timelineStartFocused: Bool

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

            timelineStartControl

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

            Text(TimeFormat.clock(engine.playheadTime + viewModel.session.timelineOrigin))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(SPTheme.textSecondary)
                .frame(minWidth: 88, alignment: .trailing)
                .help("Playhead time (includes timeline start offset)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SPTheme.panel)
    }

    /// Double-click to edit. Digits enter right-to-left; `:` / `.` stay fixed; `.00` locked.
    private var timelineStartControl: some View {
        HStack(spacing: 6) {
            Text("Timeline start")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SPTheme.textSecondary)

            if isEditingTimelineStart {
                Text(TimeFormat.formatTimelineStart(fromDigits: timelineStartDigits))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(SPTheme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: 118, alignment: .leading)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(SPTheme.accent, lineWidth: 1.5)
                    )
                    .focusable()
                    .focused($timelineStartFocused)
                    .focusEffectDisabled()
                    .onAppear {
                        viewModel.isEditingTimelineOrigin = true
                        DispatchQueue.main.async {
                            timelineStartFocused = true
                        }
                    }
                    .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                        guard let ch = press.characters.first else { return .ignored }
                        timelineStartDigits = TimeFormat.appendTimelineDigit(timelineStartDigits, ch)
                        return .handled
                    }
                    .onKeyPress(.delete) {
                        timelineStartDigits = TimeFormat.deleteTimelineDigit(timelineStartDigits)
                        return .handled
                    }
                    .onKeyPress(.deleteForward) {
                        timelineStartDigits = TimeFormat.deleteTimelineDigit(timelineStartDigits)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        commitTimelineStart()
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        cancelTimelineStartEdit()
                        return .handled
                    }
                    .onExitCommand { cancelTimelineStartEdit() }
                    .onChange(of: timelineStartFocused) { _, focused in
                        if !focused, isEditingTimelineStart {
                            commitTimelineStart()
                        }
                    }
                    .help("Type digits (right → left). Enter applies. Esc cancels.")
            } else {
                Text(TimeFormat.clockWithHours(viewModel.session.timelineOrigin))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(SPTheme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: 118, alignment: .leading)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(SPTheme.border, lineWidth: 1)
                    )
                    .help("Double-click to edit timeline start")
                    .onTapGesture(count: 2) {
                        beginTimelineStartEdit()
                    }
            }
        }
    }

    private func beginTimelineStartEdit() {
        // Start at zeros so digits fill right-to-left as typed (1 → 00:00:01.00).
        timelineStartDigits = ""
        isEditingTimelineStart = true
        viewModel.isEditingTimelineOrigin = true
    }

    private func cancelTimelineStartEdit() {
        isEditingTimelineStart = false
        timelineStartFocused = false
        viewModel.isEditingTimelineOrigin = false
        timelineStartDigits = ""
    }

    private func commitTimelineStart() {
        guard isEditingTimelineStart else { return }
        let value = TimeFormat.time(fromDigits: timelineStartDigits)
        isEditingTimelineStart = false
        timelineStartFocused = false
        viewModel.isEditingTimelineOrigin = false
        timelineStartDigits = ""
        viewModel.setTimelineOrigin(raw: TimeFormat.formatTimelineStart(fromDigits: TimeFormat.digits(fromTime: value)))
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
}
