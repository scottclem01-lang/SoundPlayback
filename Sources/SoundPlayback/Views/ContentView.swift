import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = SessionViewModel()
    @FocusState private var workspaceFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TransportBar(viewModel: viewModel, engine: viewModel.engine)
            Divider().overlay(SPTheme.border)
            TimelineWorkspaceView(viewModel: viewModel, engine: viewModel.engine)
        }
        .background(SPTheme.canvas)
        .focusable()
        .focused($workspaceFocused)
        .onAppear {
            workspaceFocused = true
            viewModel.refreshDevices()
        }
        .onKeyPress(keys: [.space]) { _ in
            viewModel.engine.togglePlayStop()
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("p")]) { _ in
            if viewModel.engine.transport == .playing {
                viewModel.engine.pause()
            } else if viewModel.engine.transport == .paused {
                viewModel.engine.play()
            }
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("m")]) { _ in
            viewModel.addMarkerAtPlayhead()
            return .handled
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard let char = press.characters.first,
                  let digit = Int(String(char)) else { return .ignored }
            let shift = press.modifiers.contains(.shift)
            viewModel.handleDigitKey(digit, shift: shift)
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
        .toolbar {
            ToolbarItemGroup {
                Button("Import…") { openImportPanel() }
                Button("Open…") { openSessionPanel() }
                Button("Save…") { saveSessionPanel() }
                Button("New") { viewModel.newSession() }
            }
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
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: SessionDocumentService.fileExtension) ?? .json
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.open(from: url)
    }

    private func saveSessionPanel() {
        if let url = viewModel.documentURL {
            viewModel.save(to: url)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: SessionDocumentService.fileExtension) ?? .json
        ]
        panel.nameFieldStringValue = "\(viewModel.session.name).\(SessionDocumentService.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.save(to: url)
    }
}
