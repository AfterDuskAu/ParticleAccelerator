import CoreAudio
import Foundation
import os

/// Hears whatever this Mac is playing: Spotify, a browser, any app.
///
/// It uses a Core Audio "process tap" (macOS 14.2 and later): a listening point on the
/// sound all the Mac's apps are sending to the speakers. The tap is wrapped in a
/// made-up device of its own, so Core Audio hands its sound over like a microphone's.
/// The tap only listens: nothing the apps play is changed or muted.
///
/// macOS asks the person once for permission ("Screen & System Audio Recording").
/// Until they allow it, the tap hears silence.
@available(macOS 14.2, *)
final class MacSoundFeed: SoundFeed {
    private var parts: Parts
    private var outputWatcher: DeviceWatcher?
    /// What `heard` needs: the ring being filled, and how long the Mac's output takes
    /// to play a sample. The stage's thread reads them while the main thread may be
    /// changing them (new speakers).
    private let heardFrom: OSAllocatedUnfairLock<HeardFrom>

    private struct HeardFrom: Sendable {
        var ring: SampleRing
        var delaySamples: Int64
    }

    /// The tap hears the sound as it's handed to the speakers, a moment before it
    /// comes out of them.
    func heard() -> Heard {
        let from = heardFrom.withLock { $0 }
        return Heard(ring: from.ring, upTo: from.ring.totalWritten - from.delaySamples, isHeldStill: false)
    }

    init() throws {
        parts = try Self.build()
        heardFrom = OSAllocatedUnfairLock(initialState: Self.heardFrom(parts))
        // New speakers or headphones can run at a different sample rate and take a
        // different time to play: start again on them.
        outputWatcher = SoundDevices.watchDefaultDevice(input: false) { [weak self] in
            self?.startAgain()
        }
    }

    deinit {
        Self.takeDown(parts)
    }

    func shutDown() {
        outputWatcher = nil
        Self.takeDown(parts)
        parts.tap = kAudioObjectUnknown
        parts.device = kAudioObjectUnknown
    }

    private func startAgain() {
        guard parts.tap != kAudioObjectUnknown else { return }
        guard let newParts = try? Self.build() else { return }
        Self.takeDown(parts)
        parts = newParts
        let from = Self.heardFrom(newParts)
        heardFrom.withLock { $0 = from }
    }

    // MARK: Building and taking down

    private struct Parts {
        var tap: AudioObjectID
        var device: AudioObjectID
        var listening: DeviceListening
    }

    private static func heardFrom(_ parts: Parts) -> HeardFrom {
        let ring = parts.listening.ring
        return HeardFrom(ring: ring, delaySamples: Int64(SoundDevices.outputDelaySeconds() * ring.sampleRate))
    }

    private static func build() throws -> Parts {
        // 1. The tap: everything every app plays, mixed down to left and right.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Particle Accelerator"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr, tap != kAudioObjectUnknown
        else {
            throw ListeningProblem(
                message: "This Mac's sound can't be heard until you allow it in System Settings → Privacy & Security → Screen & System Audio Recording.")
        }
        guard
            let format = SoundDevices.number(
                tap, kAudioTapPropertyFormat, as: AudioStreamBasicDescription.self),
            format.mSampleRate > 0, DeviceListening.isUsualFormat(format)
        else {
            AudioHardwareDestroyProcessTap(tap)
            throw ListeningProblem(
                message: "This Mac's sound can't be heard: it isn't in the usual format.")
        }

        // 2. A private device made of nothing but the tap, so it can be listened to
        //    like a microphone. It has no microphone and no speakers of its own.
        let deviceDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Particle Accelerator (listening)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[String: Any]](),
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        guard
            AudioHardwareCreateAggregateDevice(deviceDescription as CFDictionary, &device) == noErr,
            device != kAudioObjectUnknown
        else {
            AudioHardwareDestroyProcessTap(tap)
            throw ListeningProblem(message: "This Mac's sound can't be heard: Core Audio wouldn't set up the listening device.")
        }

        // 3. Copy what arrives into the ring.
        let listening = DeviceListening(device: device, sampleRate: format.mSampleRate)
        guard listening.start() else {
            AudioHardwareDestroyAggregateDevice(device)
            AudioHardwareDestroyProcessTap(tap)
            throw ListeningProblem(message: "This Mac's sound can't be heard: Core Audio wouldn't start listening.")
        }
        return Parts(tap: tap, device: device, listening: listening)
    }

    private static func takeDown(_ parts: Parts) {
        parts.listening.stop()
        if parts.device != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(parts.device) }
        if parts.tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(parts.tap) }
    }
}
