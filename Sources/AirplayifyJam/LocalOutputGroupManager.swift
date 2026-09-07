import CoreAudio
import Foundation

final class LocalOutputGroupManager {
    private let uid = "com.austinwise.airplayify.local-output"
    private(set) var activeDeviceID: AudioDeviceID?
    private var previousDefaultDeviceID: AudioDeviceID?

    func activate(_ devices: [OutputDevice], includeVirtualAudioLoopback: Bool) throws {
        deactivate()
        previousDefaultDeviceID = currentDefaultOutputDevice()
        var local = LocalOutputSelection(devices: devices).localDevices
        if includeVirtualAudioLoopback {
            guard let loopback = AudioDeviceCatalog.devices().first(where: {
                $0.name.localizedCaseInsensitiveContains("BlackHole")
            }) else {
                previousDefaultDeviceID = nil
                throw LocalOutputError.virtualAudioUnavailable
            }
            if !local.contains(where: { $0.id == loopback.id }) {
                local.append(loopback)
            }
        }
        let subdevices = local.compactMap { device -> [String: Any]? in
            guard let id = AudioDeviceID(device.id), let deviceUID = deviceUID(for: id) else { return nil }
            return [
                kAudioSubDeviceUIDKey: deviceUID,
                kAudioSubDeviceDriftCompensationKey: true
            ]
        }
        guard !subdevices.isEmpty else { throw LocalOutputError.noOutputs }
        let masterUID = subdevices.first?[kAudioSubDeviceUIDKey] as? String
        var description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Airplayify Local Outputs",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: subdevices,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false
        ]
        if let masterUID { description[kAudioAggregateDeviceMainSubDeviceKey] = masterUID }
        var aggregateID = AudioDeviceID(0)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr else { throw LocalOutputError.coreAudio(status) }
        activeDeviceID = aggregateID
        do {
            try setDefaultOutput(aggregateID)
        } catch {
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
            activeDeviceID = nil
            previousDefaultDeviceID = nil
            throw error
        }
    }

    func deactivate() {
        guard let activeDeviceID else { return }
        if let previousDefaultDeviceID {
            try? setDefaultOutput(previousDefaultDeviceID)
        }
        _ = AudioHardwareDestroyAggregateDevice(activeDeviceID)
        self.activeDeviceID = nil
        self.previousDefaultDeviceID = nil
    }

    private func currentDefaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr else { return nil }
        return deviceID
    }

    private func setDefaultOutput(_ id: AudioDeviceID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID)
        guard status == noErr else { throw LocalOutputError.coreAudio(status) }
    }

    private func deviceUID(for id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeUnretainedValue() as String?
    }
}

extension LocalOutputGroupManager: LocalOutputActivating {}

enum LocalOutputError: LocalizedError {
    case noOutputs
    case virtualAudioUnavailable
    case coreAudio(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noOutputs: return "No local HDMI, USB, or built-in outputs are selected."
        case .virtualAudioUnavailable: return "BlackHole 2ch is selected but Core Audio has not loaded it. Restart the Mac or choose Screen & System Audio."
        case .coreAudio(let status): return "Core Audio could not create the local output group (\(status))."
        }
    }
}
