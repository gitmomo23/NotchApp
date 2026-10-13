import CoreAudio
import Foundation

enum VolumeControl {
    static func read() -> Float? {
        let device = defaultOutputDevice()
        guard device != 0 else { return nil }
        return readVolume(device)
    }

    @discardableResult
    static func setVolume(_ value: Float) -> Bool {
        let device = defaultOutputDevice()
        guard device != 0 else { return false }
        return writeVolume(device, value: min(1, max(0, value)))
    }

    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        let device = defaultOutputDevice()
        guard device != 0 else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else {
            return setVolume(muted ? 0 : 0.25)
        }
        var flag: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &flag)
        return status == noErr
    }

    private static func defaultOutputDevice() -> AudioDeviceID {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        return status == noErr ? device : 0
    }

    private static func volumeAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func readVolume(_ device: AudioDeviceID) -> Float? {
        var address = volumeAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        if !AudioObjectHasProperty(device, &address) {
            address = volumeAddress(kAudioDevicePropertyVolumeScalar)
            if !AudioObjectHasProperty(device, &address) { return nil }
        }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        return status == noErr ? volume : nil
    }

    private static func writeVolume(_ device: AudioDeviceID, value: Float) -> Bool {
        var address = volumeAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        if !AudioObjectHasProperty(device, &address) {
            address = volumeAddress(kAudioDevicePropertyVolumeScalar)
        }
        var volume = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume)
        return status == noErr
    }
}
