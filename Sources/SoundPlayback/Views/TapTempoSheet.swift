import AppKit
import Combine
import SwiftUI

@MainActor
final class TapTempoController: ObservableObject {
    @Published private(set) var tapTimes: [TimeInterval] = []
    @Published var pulse = false

    var estimatedBPM: Double? { Self.bpm(from: tapTimes) }

    func reset() {
        tapTimes = []
        pulse = false
    }

    func registerTap() {
        let now = ProcessInfo.processInfo.systemUptime
        if let last = tapTimes.last, now - last < 0.08 { return }
        tapTimes.append(now)
        if tapTimes.count > 12 {
            tapTimes.removeFirst(tapTimes.count - 12)
        }
        pulse = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            pulse = false
        }
    }

    static func bpm(from tapTimes: [TimeInterval]) -> Double? {
        guard tapTimes.count >= 2 else { return nil }
        var intervals: [TimeInterval] = []
        for i in 1..<tapTimes.count {
            let dt = tapTimes[i] - tapTimes[i - 1]
            if dt >= 0.25 && dt <= 1.5 {
                intervals.append(dt)
            }
        }
        guard !intervals.isEmpty else { return nil }
        let sorted = intervals.sorted()
        let mid = sorted.count / 2
        let median: TimeInterval
        if sorted.count % 2 == 0 {
            median = (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            median = sorted[mid]
        }
        return ((60.0 / median) * 10).rounded() / 10
    }
}

struct TapTempoSheet: View {
    @ObservedObject var viewModel: SessionViewModel
    let onCancel: () -> Void
    let onConfirm: (Double) -> Void

    @StateObject private var controller = TapTempoController()
    @State private var inputMonitor: Any?

    var body: some View {
        VStack(spacing: 18) {
            Text("Tap Tempo")
                .font(.headline)

            Text("Playback is running — tap or click the trackpad to the beat.\nSpace works too.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(bpmLabel)
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .foregroundStyle(controller.estimatedBPM == nil ? SPTheme.textSecondary : SPTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            Text(tapCountLabel)
                .font(.caption)
                .foregroundStyle(SPTheme.textSecondary)

            RoundedRectangle(cornerRadius: 10)
                .fill(controller.pulse ? SPTheme.accent.opacity(0.35) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SPTheme.accent.opacity(0.7), lineWidth: 2)
                )
                .overlay(
                    Text("TAP")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(SPTheme.textPrimary)
                )
                .frame(height: 140)
                .allowsHitTesting(false)

            HStack {
                Button("Reset") { controller.reset() }
                    .disabled(controller.tapTimes.isEmpty)

                Spacer()

                Button("Cancel", role: .cancel) {
                    finish(confirm: false)
                }
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    finish(confirm: true)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(controller.estimatedBPM == nil)
            }
        }
        .padding(22)
        .frame(width: 420)
        .onAppear {
            controller.reset()
            viewModel.play()
            installInputMonitor()
        }
        .onDisappear {
            removeInputMonitor()
        }
    }

    private var bpmLabel: String {
        guard let bpm = controller.estimatedBPM else { return "—" }
        if abs(bpm - bpm.rounded()) < 0.05 {
            return "\(Int(bpm.rounded()))"
        }
        return String(format: "%.1f", bpm)
    }

    private var tapCountLabel: String {
        let n = controller.tapTimes.count
        if n == 0 { return "Waiting for taps…" }
        if n == 1 { return "1 tap — keep going" }
        return "\(n) taps"
    }

    private func finish(confirm: Bool) {
        removeInputMonitor()
        viewModel.stop()
        if confirm, let bpm = controller.estimatedBPM {
            onConfirm(bpm)
        } else {
            onCancel()
        }
    }

    private func installInputMonitor() {
        removeInputMonitor()
        // Trackpad tap-to-click arrives as leftMouseDown; Space as keyDown.
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            if event.type == .keyDown {
                if event.keyCode == 49 {
                    Task { @MainActor in
                        controller.registerTap()
                    }
                    return nil
                }
                return event
            }

            if event.type == .leftMouseDown {
                if Self.shouldIgnoreMouseTap(event) {
                    return event
                }
                Task { @MainActor in
                    controller.registerTap()
                }
                return event
            }
            return event
        }
    }

    private func removeInputMonitor() {
        if let inputMonitor {
            NSEvent.removeMonitor(inputMonitor)
            self.inputMonitor = nil
        }
    }

    /// Ignore Reset / Cancel / OK (and the bottom chrome) so those clicks aren't counted as beats.
    private static func shouldIgnoreMouseTap(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        // AppKit coords: origin at bottom-left. Button row sits in the lower inset.
        if event.locationInWindow.y < 70 {
            return true
        }
        guard let content = window.contentView else { return false }
        var view: NSView? = content.hitTest(event.locationInWindow)
        while let current = view {
            if current is NSButton { return true }
            let name = String(describing: type(of: current))
            if name.contains("Button") { return true }
            view = current.superview
        }
        return false
    }
}
