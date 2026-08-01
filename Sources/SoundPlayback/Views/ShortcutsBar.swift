import SwiftUI

struct ShortcutsBar: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                shortcut("Space", "Play / Stop")
                shortcut("P", "Pause")
                shortcut("M", "Mark")
                shortcut("1–0", "Jump 1–10")
                shortcut("⇧1–0", "Jump 11–20")
                shortcut("⌘Z", "Undo edit")
                shortcut("⌃/⌘-click", "Multi-select clips")
                shortcut("⌘C", "Copy clip")
                shortcut("⌘V", "Paste at playhead")
                shortcut("Delete", "Remove clip")
                shortcut("Pinch", "Zoom")
                Text("Click empty lane · set playhead")
                    .foregroundStyle(SPTheme.textSecondary)
                Text("Double-click clicks/thump · edit tempo")
                    .foregroundStyle(SPTheme.textSecondary)
                Text("Drag mark · pull up to delete")
                    .foregroundStyle(SPTheme.textSecondary)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(SPTheme.panel.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SPTheme.border)
                .frame(height: 1)
        }
    }

    private func shortcut(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1))
                .cornerRadius(3)
                .foregroundStyle(SPTheme.textPrimary)
            Text(label)
                .foregroundStyle(SPTheme.textSecondary)
        }
    }
}
