import SwiftUI

struct TrackHeaderView: View {
    let track: Track
    let availableOutputs: Int
    let canDelete: Bool
    /// Rename only while transport is stopped.
    let canBeginRename: Bool
    let onVolume: (Double) -> Void
    let onMute: (Bool) -> Void
    let onSolo: (Bool) -> Void
    let onToggleOutput: (Int) -> Void
    let onRename: (String) -> Void
    let onRenameEditingChanged: (Bool) -> Void
    let onDelete: () -> Void

    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    private var isGeneratedTrack: Bool {
        track.clips.contains(where: \.isGenerated)
    }

    private var headerAccent: Color {
        guard let kind = track.clips.compactMap(\.generation?.kind).first else {
            return SPTheme.panel
        }
        switch kind {
        case .introClicks: return SPTheme.clipFillClicks.opacity(0.35)
        case .thump: return SPTheme.clipFillThump.opacity(0.35)
        case .timecode: return SPTheme.clipFillTimecode.opacity(0.35)
        }
    }

    private var generatedBadgeLabel: String? {
        let kinds = Set(track.clips.compactMap(\.generation?.kind))
        if kinds.contains(.timecode) { return "LTC" }
        if kinds.contains(.introClicks) || kinds.contains(.thump) { return "BPM" }
        return nil
    }

    private var generatedBadgeHelp: String {
        generatedBadgeLabel == "LTC"
            ? "Double-click the clip to edit timecode"
            : "Double-click the clip to edit tempo"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                trackNameLabel
                if let badge = generatedBadgeLabel {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(SPTheme.textSecondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(3)
                        .help(generatedBadgeHelp)
                }
                Spacer(minLength: 0)
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SPTheme.textSecondary)
                        .frame(width: 16, height: 16)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .disabled(!canDelete)
                .opacity(canDelete ? 1 : 0.35)
                .help(canDelete ? "Delete track" : "At least one track is required")
            }

            HStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    Slider(
                        value: Binding(
                            get: { track.volume },
                            set: { onVolume($0) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.mini)

                    // Unity tick at 80%
                    GeometryReader { geo in
                        Rectangle()
                            .fill(SPTheme.textSecondary)
                            .frame(width: 1.5, height: 7)
                            .position(x: geo.size.width * 0.8, y: geo.size.height * 0.5)
                    }
                    .allowsHitTesting(false)
                }
                Text(volumeLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SPTheme.textSecondary)
                    .frame(width: 28, alignment: .trailing)
            }

            HStack(spacing: 6) {
                ToggleChip(title: "M", isOn: track.isMuted, activeColor: .orange) {
                    onMute(!track.isMuted)
                }
                ToggleChip(title: "S", isOn: track.isSoloed, activeColor: .yellow) {
                    onSolo(!track.isSoloed)
                }
                ForEach(1...4, id: \.self) { channel in
                    let enabled = channel <= availableOutputs
                    let isOn = track.outputMask.contains(.channel(channel))
                    Button {
                        onToggleOutput(channel)
                    } label: {
                        Text("\(channel)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .frame(width: 18, height: 18)
                            .background(isOn && enabled ? SPTheme.accent.opacity(0.85) : Color.white.opacity(0.08))
                            .foregroundStyle(enabled ? SPTheme.textPrimary : SPTheme.textSecondary.opacity(0.35))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(SPTheme.border, lineWidth: 1)
                            )
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                }
            }
        }
        .padding(10)
        .frame(width: SPTheme.headerWidth, height: SPTheme.trackHeight, alignment: .topLeading)
        .background(isGeneratedTrack ? headerAccent : SPTheme.panel)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SPTheme.border)
                .frame(width: 1)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SPTheme.border)
                .frame(height: 1)
        }
    }

    private var trackNameLabel: some View {
        Group {
            if isEditingName {
                TextField("Track name", text: $draftName)
                    .font(.caption.weight(.semibold))
                    .textFieldStyle(.plain)
                    .focused($nameFieldFocused)
                    .onSubmit { commitNameEdit() }
                    .onExitCommand { cancelNameEdit() }
                    .onAppear {
                        DispatchQueue.main.async {
                            nameFieldFocused = true
                        }
                    }
                    .onChange(of: nameFieldFocused) { _, focused in
                        if !focused { commitNameEdit() }
                    }
            } else {
                Text(track.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SPTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(
                        canBeginRename
                            ? "\(track.name)\nDouble-click to rename"
                            : "\(track.name)\nStop playback to rename"
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        guard canBeginRename else { return }
                        beginNameEdit()
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: canBeginRename) { _, allowed in
            // If playback starts mid-edit, commit and leave text mode.
            if !allowed, isEditingName {
                commitNameEdit()
            }
        }
    }

    private func beginNameEdit() {
        draftName = track.name
        isEditingName = true
        onRenameEditingChanged(true)
    }

    private func commitNameEdit() {
        guard isEditingName else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingName = false
        nameFieldFocused = false
        if !trimmed.isEmpty, trimmed != track.name {
            onRename(trimmed)
        } else {
            draftName = track.name
        }
        onRenameEditingChanged(false)
    }

    private func cancelNameEdit() {
        guard isEditingName else { return }
        isEditingName = false
        nameFieldFocused = false
        draftName = track.name
        onRenameEditingChanged(false)
    }

    private var volumeLabel: String {
        // 80 is unity — show "U" when parked on the tick.
        abs(track.volume - 0.8) < 0.015 ? "U" : "\(Int((track.volume * 100).rounded()))"
    }
}

private struct ToggleChip: View {
    let title: String
    let isOn: Bool
    var activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(width: 18, height: 18)
                .background(isOn ? activeColor.opacity(0.85) : Color.white.opacity(0.08))
                .foregroundStyle(SPTheme.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(SPTheme.border, lineWidth: 1)
                )
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
}
