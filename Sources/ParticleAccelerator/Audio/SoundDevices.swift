import CoreAudio
import Foundation

/// Plain questions to Core Audio about this Mac's sound devices.
enum SoundDevices {
    /// The device sound is played through (System Settings → Sound → Output), if any.
    static var defaultOutput: AudioDeviceID? {
        device(kAudioHardwarePropertyDefaultOutputDevice)
    }

    /// The device sound is heard through (System Settings → Sound → Input), if any.
    static var defaultInput: AudioDeviceID? {
        device(kAudioHardwarePropertyDefaultInputDevice)
    }

    static func name(of device: AudioDeviceID) -> String? {
        string(device, kAudioObjectPropertyName)
    }

    /// Whether the device is connected by Bluetooth. Listening to a Bluetooth headset's
    /// microphone makes macOS switch the headset to call quality, which spoils whatever
    /// the person is hearing through it.
    static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        let transport = number(device, kAudioDevicePropertyTransportType, as: UInt32.self)
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// The Mac's own microphone, if it has one (a Mac mini or Mac Studio doesn't).
    static var builtInMicrophone: AudioDeviceID? {
        allDevices.first { device in
            number(device, kAudioDevicePropertyTransportType, as: UInt32.self)
                == kAudioDeviceTransportTypeBuiltIn
                && firstStream(of: device, scope: kAudioObjectPropertyScopeInput) != nil
        }
    }

    private static var allDevices: [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else {
            return []
        }
        return devices
    }

    /// How many samples a second the device runs at.
    static func sampleRate(of device: AudioDeviceID) -> Double? {
        let rate = number(device, kAudioDevicePropertyNominalSampleRate, as: Float64.self)
        return rate.flatMap { $0 > 0 ? $0 : nil }
    }

    /// How long sound takes to come out of the speakers after it's handed to the Mac's
    /// sound output, in seconds. Built-in speakers take a few hundredths of a second;
    /// Bluetooth headphones can take a fifth of a second.
    ///
    /// Asking takes a handful of calls to Core Audio, so ask when the output changes,
    /// not every frame.
    static func outputDelaySeconds() -> Double {
        guard let device = defaultOutput, let rate = sampleRate(of: device) else { return 0 }
        let output = kAudioObjectPropertyScopeOutput
        var frames = number(device, kAudioDevicePropertyLatency, scope: output, as: UInt32.self) ?? 0
        frames += number(device, kAudioDevicePropertySafetyOffset, scope: output, as: UInt32.self) ?? 0
        frames += number(device, kAudioDevicePropertyBufferFrameSize, as: UInt32.self) ?? 0
        if let stream = firstStream(of: device, scope: output) {
            frames += number(stream, kAudioStreamPropertyLatency, as: UInt32.self) ?? 0
        }
        // Core Audio's numbers are trusted up to a second; past that something's wrong.
        return min(1, Double(frames) / rate)
    }

    /// Calls `changed` on the main thread whenever the Mac's output or input device
    /// changes (headphones plugged in, a different microphone chosen). Keep the
    /// returned watcher for as long as the calls are wanted.
    static func watchDefaultDevice(input: Bool, changed: @escaping () -> Void) -> DeviceWatcher {
        DeviceWatcher(
            selector: input
                ? kAudioHardwarePropertyDefaultInputDevice
                : kAudioHardwarePropertyDefaultOutputDevice,
            changed: changed)
    }

    // MARK: Asking Core Audio

    private static func device(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        let device = number(AudioObjectID(kAudioObjectSystemObject), selector, as: AudioDeviceID.self)
        return device.flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    static func number<Value>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, as type: Value.Type
    ) -> Value? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Value>.size)
        let value = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr,
            size == UInt32(MemoryLayout<Value>.size)
        else { return nil }
        return value.pointee
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector)
        -> String?
    {
        // Core Audio hands back a string the caller then owns.
        number(object, selector, as: Unmanaged<CFString>.self)?.takeRetainedValue() as String?
    }

    private static func firstStream(of device: AudioDeviceID, scope: AudioObjectPropertyScope)
        -> AudioStreamID?
    {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams, mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
            size >= UInt32(MemoryLayout<AudioStreamID>.size)
        else { return nil }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams) == noErr else {
            return nil
        }
        return streams.first
    }
}

/// Watches for the Mac's output or input device changing. It stops watching when it's
/// let go of.
final class DeviceWatcher {
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    fileprivate init(selector: AudioObjectPropertySelector, changed: @escaping () -> Void) {
        address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        block = { _, _ in changed() }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
    }
}
