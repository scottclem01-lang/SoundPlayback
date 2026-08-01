import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var session: PlaybackSession
    @Published var documentURL: URL?
    @Published var outputDevices: [AudioOutputDevice] = []
    @Published var selectedDeviceUID: String?
    @Published var errorMessage: String?
    @Published var pixelsPerSecond: Double = 80

    let engine = PlaybackEngine()

    var selectedDevice: AudioOutputDevice? {
        guard let selectedDeviceUID else { return nil }
        return outputDevices.first { $0.uid == selectedDeviceUID }
    }

    /// Outs beyond the selected device’s channel count are unavailable in the UI.
    var availableOutputCount: Int {
        selectedDevice?.usableOutputSlots ?? 2
    }

    init(session: PlaybackSession = .blank()) {
        self.session = session
        refreshDevices()
        if let uid = session.outputDeviceUID,
           outputDevices.contains(where: { $0.uid == uid }) {
            selectedDeviceUID = uid
        } else {
            selectedDeviceUID = outputDevices.first?.uid
        }
        engine.setPlayStart(session.playStartTime)
    }

    func refreshDevices() {
        outputDevices = AudioDeviceService.outputDevices()
        if let selectedDeviceUID,
           !outputDevices.contains(where: { $0.uid == selectedDeviceUID }) {
            self.selectedDeviceUID = outputDevices.first?.uid
        }
    }

    func selectDevice(_ uid: String?) {
        selectedDeviceUID = uid
        session.outputDeviceUID = uid
    }

    // MARK: - Tracks

    func addTrack() {
        let index = session.tracks.count + 1
        session.tracks.append(Track(name: "Track \(index)"))
    }

    func toggleOutput(trackID: UUID, channel: Int) {
        guard (1...4).contains(channel), channel <= availableOutputCount else { return }
        guard let idx = session.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        session.tracks[idx].outputMask.formSymmetricDifference(.channel(channel))
    }

    // MARK: - Transport / markers

    func setPlayStart(at time: TimeInterval) {
        let t = max(0, time)
        session.playStartTime = t
        engine.setPlayStart(t)
    }

    func addMarkerAtPlayhead() {
        let time = engine.transport == .stopped ? session.playStartTime : engine.playheadTime
        let nextNumber = (session.markers.map(\.number).max() ?? 0) + 1
        session.markers.append(TimelineMarker(number: nextNumber, time: time))
        session.markers.sort()
    }

    func jumpToMarker(number: Int) {
        guard let marker = session.markers.first(where: { $0.number == number }) else { return }
        setPlayStart(at: marker.time)
        if engine.transport == .playing {
            // Stay playing from the new start on next engine pass; for now snap playhead.
            engine.playheadTime = marker.time
        }
    }

    func handleDigitKey(_ digit: Int, shift: Bool) {
        guard let number = TimelineMarker.numberForKey(digit: digit, shift: shift) else { return }
        jumpToMarker(number: number)
    }

    // MARK: - Import (stub: creates empty-duration-safe clips once file probing exists)

    func importAudio(urls: [URL], ontoTrackIndex startTrack: Int = 0) {
        // Real import (channel split, duration probe) lands with the file reader.
        // For now, place placeholder mono clips so the timeline UI can be wired.
        var trackIndex = startTrack
        for url in urls {
            ensureTrackCount(trackIndex + 1)
            let clip = AudioClip(
                sourceURL: url,
                sourceChannel: 0,
                timelineStart: session.playStartTime,
                sourceIn: 0,
                duration: 4,
                sourceDuration: 4
            )
            session.tracks[trackIndex].clips.append(clip)
            trackIndex += 1
        }
    }

    private func ensureTrackCount(_ count: Int) {
        while session.tracks.count < count {
            addTrack()
        }
    }

    // MARK: - Document

    func newSession() {
        session = .blank()
        documentURL = nil
        engine.stop()
        engine.setPlayStart(0)
        selectedDeviceUID = outputDevices.first?.uid
        session.outputDeviceUID = selectedDeviceUID
    }

    func save(to url: URL) {
        do {
            try SessionDocumentService.save(session, to: url)
            documentURL = url
            session.name = url.deletingPathExtension().lastPathComponent
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(from url: URL) {
        do {
            let loaded = try SessionDocumentService.load(from: url)
            session = loaded
            documentURL = url
            engine.stop()
            engine.setPlayStart(loaded.playStartTime)
            if let uid = loaded.outputDeviceUID,
               outputDevices.contains(where: { $0.uid == uid }) {
                selectedDeviceUID = uid
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
