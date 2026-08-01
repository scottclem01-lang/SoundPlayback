import SwiftUI

struct ImportPlacementSheet: View {
    let pending: PendingImport
    let trackCount: Int
    let trackHasAudio: (Int) -> Bool
    let onCancel: () -> Void
    let onConfirm: (ImportPlacementChoice) -> Void

    @State private var selectedMonoTrack = 0
    @State private var selectedPairStart = 0
    @State private var resolution: ImportConflictResolution = .append

    private var pairOptions: [Int] {
        let pairs = max(1, (trackCount + 1) / 2)
        // Always offer at least current pairs plus one empty pair slot.
        return Array(stride(from: 0, to: max(trackCount + 1, pairs * 2), by: 2))
    }

    private var destinationOccupied: Bool {
        if pending.isStereo {
            return trackHasAudio(selectedPairStart) || trackHasAudio(selectedPairStart + 1)
        }
        return trackHasAudio(selectedMonoTrack)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Place Import")
                .font(.headline)

            Text(pending.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(pending.isStereo ? "Stereo — locked pair" : "Mono — single track")
                .font(.caption)
                .foregroundStyle(.secondary)

            if pending.isStereo {
                Picker("Track pair", selection: $selectedPairStart) {
                    ForEach(pairOptions, id: \.self) { start in
                        Text("Tracks \(start + 1)–\(start + 2)").tag(start)
                    }
                }
                .pickerStyle(.radioGroup)
            } else {
                Picker("Track", selection: $selectedMonoTrack) {
                    ForEach(0..<max(trackCount, 1), id: \.self) { index in
                        Text("Track \(index + 1)").tag(index)
                    }
                    Text("Track \(trackCount + 1) (new)").tag(trackCount)
                }
                .pickerStyle(.radioGroup)
            }

            if destinationOccupied {
                Text("Destination already has audio")
                    .font(.caption.weight(.semibold))
                Picker("Existing audio", selection: $resolution) {
                    Text("Replace").tag(ImportConflictResolution.replace)
                    Text("Append").tag(ImportConflictResolution.append)
                }
                .pickerStyle(.radioGroup)
                Text(resolution == .replace
                       ? "Removes existing clips on the destination, then places the new audio."
                       : "Places the new audio after the last clip on the destination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Import") {
                    let mode: ImportPlacementMode = pending.isStereo
                        ? .stereoPair(startTrackIndex: selectedPairStart)
                        : .mono(trackIndex: selectedMonoTrack)
                    onConfirm(ImportPlacementChoice(
                        mode: mode,
                        resolution: destinationOccupied ? resolution : .append
                    ))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            selectedMonoTrack = 0
            selectedPairStart = 0
            resolution = .append
        }
    }
}
