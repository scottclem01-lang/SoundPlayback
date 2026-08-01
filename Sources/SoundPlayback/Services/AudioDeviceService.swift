import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Hashable {
    var id: String { uid }
    let uid: String
    let name: String
    let outputChannelCount: Int

    var usableOutputSlots: Int { min(4, max(0, outputChannelCount)) }
}

/// Enumerates Core Audio output devices independently of the system default.
enum AudioDeviceService {
    static func outputDevices() -> [AudioOutputDevice] {
        deviceList().compactMap { deviceID -> AudioOutputDevice? in
            let channels = outputChannelCount(deviceID)
            guard channels > 0 else { return nil }
            let uid = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) ?? "\(deviceID)"
            let name = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceNameCFString)
                ?? "Device \(deviceID)"
            return AudioOutputDevice(uid: uid, name: name, outputChannelCount: channels)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func device(uid: String) -> AudioOutputDevice? {
        outputDevices().first { $0.uid == uid }
    }

    // MARK: - Core Audio helpers

    private static func deviceList() -> [AudioDeviceID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &devices
        ) == noErr else { return [] }
        return devices
    }

    private static func outputChannelCount(_ deviceID: AudioDeviceID) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return 0 }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, raw) == noErr else {
            return 0
        }

        let abl = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var channels = 0
        for buffer in UnsafeMutableAudioBufferListPointer(abl) {
            channels += Int(buffer.mNumberChannels)
        }
        return channels
    }

    private static func stringProperty(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<CFString?>.stride)
        var cfValue: CFString?
        let status = withUnsafeMutablePointer(to: &cfValue) { ptr -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, ptr)
        }
        guard status == noErr, let cfValue else { return nil }
        return cfValue as String
    }
}
