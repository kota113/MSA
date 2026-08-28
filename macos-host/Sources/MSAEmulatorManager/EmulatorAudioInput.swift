import CoreAudio
import Foundation

struct EmulatorAudioInput: Equatable, Sendable {
    enum AudioInputError: LocalizedError {
        case deviceUnavailable(String)
        case selectionFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .deviceUnavailable(let uid):
                return "The selected microphone is no longer available: \(uid)"
            case .selectionFailed(let status):
                return "Could not select the macOS microphone (CoreAudio error \(status))."
            }
        }
    }

    let uid: String
    let name: String

    static func availableDevices() -> [EmulatorAudioInput] {
        allDeviceIDs().compactMap { deviceID in
            guard hasInputStreams(deviceID),
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, for: deviceID),
                  let name = stringProperty(kAudioObjectPropertyName, for: deviceID) else { return nil }
            return EmulatorAudioInput(uid: uid, name: name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultDeviceUID() -> String? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                         &size, &deviceID) == noErr else { return nil }
        return stringProperty(kAudioDevicePropertyDeviceUID, for: deviceID)
    }

    static func selectDevice(uid: String) throws {
        guard let deviceID = allDeviceIDs().first(where: {
            stringProperty(kAudioDevicePropertyDeviceUID, for: $0) == uid && hasInputStreams($0)
        }) else {
            throw AudioInputError.deviceUnavailable(uid)
        }
        var selectedDeviceID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size),
                                                &selectedDeviceID)
        guard status == noErr else { throw AudioInputError.selectionFailed(status) }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                             &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        let status = deviceIDs.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                       &size, buffer.baseAddress!)
        }
        guard status == noErr else { return [] }
        return deviceIDs
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector,
                                       for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value?.takeUnretainedValue() as String?
    }
}