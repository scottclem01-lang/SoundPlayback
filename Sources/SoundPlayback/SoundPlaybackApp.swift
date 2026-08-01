import AppKit
import SwiftUI

@main
struct SoundPlaybackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    /// Returns `true` when quit may proceed (saved / discarded / not dirty).
    var unsavedChangesHandler: (() -> Bool)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        bringAppToFront()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        bringAppToFront()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let unsavedChangesHandler, !unsavedChangesHandler() {
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func bringAppToFront() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}
