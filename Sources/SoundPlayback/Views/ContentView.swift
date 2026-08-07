import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = SessionViewModel()
    @FocusState private var workspaceFocused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            ToolsBar(
                detectedTempoBPM: viewModel.detectedTempoBPM,
                onAddIntroClicks: { viewModel.showIntroClicksSheet = true },
                onAddThumpTrack: { viewModel.showThumpTrackSheet = true },
                onGenerateTimecode: { viewModel.showTimecodeSheet = true },
                onTapTempo: { viewModel.showTapTempoSheet = true }
            )
            ShortcutsBar()
            TransportBar(viewModel: viewModel, engine: viewModel.engine)
            Divider().overlay(SPTheme.border)
            TimelineWorkspaceView(viewModel: viewModel, engine: viewModel.engine)
        }
        .background(SPTheme.canvas)
        .background(WindowCloseGuard(shouldClose: {
            viewModel.confirmDiscardOrSave { viewModel.saveInteractive() }
        }))
        .focusable()
        .focused($workspaceFocused)
        .focusEffectDisabled()
        .onAppear {
            workspaceFocused = true
            viewModel.refreshDevices()
            AppDelegate.shared?.unsavedChangesHandler = { [weak viewModel] in
                guard let viewModel else { return true }
                return viewModel.confirmDiscardOrSave { viewModel.saveInteractive() }
            }
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: viewModel.isEditingInlineText) { _, editing in
            if editing {
                workspaceFocused = false
            } else {
                // Return keyboard to transport / marker shortcuts after rename / note edit.
                DispatchQueue.main.async {
                    workspaceFocused = true
                }
            }
        }
        .onDeleteCommand {
            guard !viewModel.isEditingInlineText else { return }
            viewModel.deleteSelectedClips()
        }
        .onKeyPress(keys: [.space]) { _ in
            guard !viewModel.isEditingInlineText else { return .ignored }
            viewModel.togglePlayStop()
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("p")]) { _ in
            guard !viewModel.isEditingInlineText else { return .ignored }
            if viewModel.engine.transport == .playing {
                viewModel.pause()
            } else if viewModel.engine.transport == .paused {
                viewModel.play()
            }
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("m")]) { _ in
            guard !viewModel.isEditingInlineText else { return .ignored }
            viewModel.addMarkerAtPlayhead()
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("z")], phases: .down) { press in
            guard !viewModel.isEditingInlineText else { return .ignored }
            guard press.modifiers.contains(.command) else { return .ignored }
            viewModel.undoClipEdit()
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("c")], phases: .down) { press in
            guard !viewModel.isEditingInlineText else { return .ignored }
            guard press.modifiers.contains(.command) else { return .ignored }
            viewModel.copySelectedClips()
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("v")], phases: .down) { press in
            guard !viewModel.isEditingInlineText else { return .ignored }
            guard press.modifiers.contains(.command) else { return .ignored }
            viewModel.pasteClipsAtPlayhead()
            return .handled
        }
        .onKeyPress(.delete) {
            guard !viewModel.isEditingInlineText else { return .ignored }
            viewModel.deleteSelectedClips()
            return .handled
        }
        .onKeyPress(.deleteForward) {
            guard !viewModel.isEditingInlineText else { return .ignored }
            viewModel.deleteSelectedClips()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard !viewModel.isEditingInlineText else { return .ignored }
            viewModel.nudgePlayheadByFrames(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !viewModel.isEditingInlineText else { return .ignored }
            viewModel.nudgePlayheadByFrames(1)
            return .handled
        }
        // Unshifted digits + Shift punctuation (!@#…) → markers 1–20
        .onKeyPress(characters: CharacterSet(charactersIn: "0123456789!@#$%^&*()"), phases: .down) { press in
            guard !viewModel.isEditingInlineText else { return .ignored }
            guard let ch = press.characters.first,
                  let number = TimelineMarker.numberForCharacter(ch) else { return .ignored }
            viewModel.jumpToMarker(number: number)
            return .handled
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(item: $viewModel.pendingImport) { pending in
            ImportPlacementSheet(
                pending: pending,
                trackCount: viewModel.session.tracks.count,
                trackHasAudio: { viewModel.trackHasAudio(at: $0) },
                onCancel: { viewModel.cancelPendingImport() },
                onConfirm: { viewModel.confirmPendingImport($0) }
            )
        }
        .sheet(isPresented: $viewModel.showIntroClicksSheet) {
            IntroClicksSheet(
                trackCount: viewModel.session.tracks.count,
                initialTempoBPM: viewModel.detectedTempoBPM ?? 120,
                onCancel: { viewModel.showIntroClicksSheet = false },
                onConfirm: { request in
                    viewModel.showIntroClicksSheet = false
                    viewModel.addIntroClicks(request)
                }
            )
        }
        .sheet(isPresented: $viewModel.showThumpTrackSheet) {
            ThumpTrackSheet(
                trackCount: viewModel.session.tracks.count,
                initialTempoBPM: viewModel.detectedTempoBPM ?? 120,
                onCancel: { viewModel.showThumpTrackSheet = false },
                onConfirm: { request in
                    viewModel.showThumpTrackSheet = false
                    viewModel.addThumpTrack(request)
                }
            )
        }
        .sheet(isPresented: $viewModel.showTimecodeSheet) {
            TimecodeTrackSheet(
                trackCount: viewModel.session.tracks.count,
                projectFrameRate: viewModel.session.timelineFrameRate,
                lockedDisplaySeconds: viewModel.placementDisplaySeconds,
                onCancel: { viewModel.showTimecodeSheet = false },
                onConfirm: { request in
                    viewModel.showTimecodeSheet = false
                    viewModel.addTimecodeTrack(request)
                }
            )
        }
        .sheet(item: $viewModel.pendingGeneratedEdit) { edit in
            EditGeneratedClipSheet(
                request: edit,
                projectFrameRate: viewModel.session.timelineFrameRate,
                lockedDisplaySeconds: viewModel.displaySecondsForClip(id: edit.id),
                onCancel: { viewModel.pendingGeneratedEdit = nil },
                onConfirm: { updated in
                    viewModel.applyGeneratedEdit(updated)
                }
            )
        }
        .sheet(isPresented: $viewModel.showTapTempoSheet) {
            TapTempoSheet(
                viewModel: viewModel,
                onCancel: { viewModel.showTapTempoSheet = false },
                onConfirm: { bpm in
                    viewModel.setDetectedTempoBPM(bpm)
                    viewModel.showTapTempoSheet = false
                }
            )
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Import…") { openImportPanel() }
                Button("Open…") { openSessionPanel() }
                Button(viewModel.documentURL == nil ? "Save…" : "Save") {
                    _ = viewModel.saveInteractive()
                }
                Button("New") { newSession() }
            }
        }
    }

    private func newSession() {
        guard viewModel.confirmDiscardOrSave(performSave: { viewModel.saveInteractive() }) else { return }
        viewModel.newSession()
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak viewModel] event in
            guard let viewModel else { return event }

            // Never intercept typing in any text field / field editor.
            if Self.isTypingInTextInput() || viewModel.isEditingInlineText {
                return event
            }

            // Backspace (51) and Forward Delete (117)
            if event.keyCode == 51 || event.keyCode == 117 {
                guard !viewModel.selectedClipIDs.isEmpty else { return event }
                viewModel.deleteSelectedClips()
                return nil
            }

            // Left / Right arrows — nudge playhead 0.5s.
            if event.keyCode == 123 {
                viewModel.nudgePlayheadByFrames(-1)
                return nil
            }
            if event.keyCode == 124 {
                viewModel.nudgePlayheadByFrames(1)
                return nil
            }

            // Digits / Shift+digits → jump to markers 1–20.
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !mods.contains(.command), !mods.contains(.option), !mods.contains(.control) {
                if let digit = TimelineMarker.digitForKeyCode(event.keyCode) {
                    viewModel.handleDigitKey(digit, shift: mods.contains(.shift))
                    return nil
                }
                if let chars = event.characters,
                   let ch = chars.first,
                   let number = TimelineMarker.numberForCharacter(ch) {
                    viewModel.jumpToMarker(number: number)
                    return nil
                }
            }

            // ⌘C / ⌘V — copy selected clip(s), paste on same track(s) at playhead
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "c":
                    viewModel.copySelectedClips()
                    return nil
                case "v":
                    viewModel.pasteClipsAtPlayhead()
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }

    /// True when AppKit/SwiftUI text input owns the keyboard (incl. field editor).
    private static func isTypingInTextInput() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSText || responder is NSTextView || responder is NSTextField {
            return true
        }
        let name = NSStringFromClass(type(of: responder))
        return name.contains("Text") || name.contains("FieldEditor")
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func openImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.wav, .mp3, .audio]
        guard panel.runModal() == .OK else { return }
        viewModel.importAudio(urls: panel.urls)
    }

    private func openSessionPanel() {
        guard viewModel.confirmDiscardOrSave(performSave: { viewModel.saveInteractive() }) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: SessionDocumentService.fileExtension) ?? .json
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.open(from: url)
    }
}
