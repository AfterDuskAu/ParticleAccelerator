import CoreAudio
import Foundation

/// Copies the sound arriving at a Core Audio device into a `SampleRing`. The device is
/// a microphone, or the made-up device that carries this Mac's own sound.
///
/// Core Audio calls the copying block directly on its real-time audio thread, about a
/// hundred times a second.
final class DeviceListening {
    let ring: SampleRing
    private let device: AudioDeviceID
    private var ioProc: AudioDeviceIOProcID?

    init(device: AudioDeviceID, sampleRate: Double) {
        self.device = device
        ring = SampleRing(sampleRate: sampleRate)
    }

    deinit {
        stop()
    }

    /// Starts copying. Returns false if Core Audio won't start the device.
    func start() -> Bool {
        guard ioProc == nil else { return true }
        let ring = self.ring
        var newProc: AudioDeviceIOProcID?
        // No queue is given, so the block runs on the audio thread itself. Nothing in
        // it may allocate memory, lock, or wait (CLAUDE.md rule 6).
        let made = AudioDeviceCreateIOProcIDWithBlock(&newProc, device, nil) {
            _, input, _, output, _ in
            let heard = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            if let first = heard.first {
                ring.write(heard, frameCount: Self.frameCount(of: first))
            }
            // This only listens. If the device can also play, give it silence.
            for buffer in UnsafeMutableAudioBufferListPointer(output) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
        }
        guard made == noErr, let newProc else { return false }
        guard AudioDeviceStart(device, newProc) == noErr else {
            AudioDeviceDestroyIOProcID(device, newProc)
            return false
        }
        ioProc = newProc
        return true
    }

    func stop() {
        guard let ioProc else { return }
        AudioDeviceStop(device, ioProc)
        AudioDeviceDestroyIOProcID(device, ioProc)
        self.ioProc = nil
    }

    /// How many samples per channel a buffer of 32-bit sound holds.
    static func frameCount(of buffer: AudioBuffer) -> Int {
        guard buffer.mNumberChannels > 0 else { return 0 }
        return Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * Int(buffer.mNumberChannels))
    }

    /// Whether a sound format is the usual one: 32-bit floating-point numbers. The ring
    /// reads nothing else.
    static func isUsualFormat(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mBitsPerChannel == 32
    }
}
