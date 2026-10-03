import AVFoundation
import CoreAudio
import Testing

@testable import ParticleAccelerator

/// Some CI machines have no sound output at all. This asks Core Audio which device
/// sound goes to, without starting anything.
let macHasSoundOutput: Bool = {
    var device = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
    return status == noErr && device != kAudioObjectUnknown
}()

/// A folder of the test's own in the Mac's temporary place. It's removed when the
/// test lets go of it.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParticleAcceleratorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func file(_ name: String) -> URL {
        url.appendingPathComponent(name)
    }
}

/// Writes sound to a file, losing nothing (32-bit numbers, as given). The files are
/// only ever played muted, so the tests make no sound.
func writeSoundFile(left: [Float], right: [Float], sampleRate: Double, to url: URL) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
    let frames = AVAudioFrameCount(left.count)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    let channels = try #require(buffer.floatChannelData)
    for frame in 0..<left.count {
        channels[0][frame] = left[frame]
        channels[1][frame] = right[frame]
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}

/// A pure tone at any sample rate, starting at its loudest so the very first sample
/// isn't zero.
func tone(hz: Double, amplitude: Float, seconds: Double, sampleRate: Double) -> [Float] {
    (0..<Int(seconds * sampleRate)).map { index in
        amplitude * Float(cos(2 * Double.pi * hz * Double(index) / sampleRate))
    }
}

/// Collects everything a ring hears, on a thread of its own, the way an analyser would.
final class RingRecorder: @unchecked Sendable {
    private let ring: SampleRing
    private let queue = DispatchQueue(label: "ring recorder")
    private let timer: DispatchSourceTimer
    private var heard: [Float] = []
    private var collectedUpTo: Int64 = 0
    private var missedSome = false

    init(ring: SampleRing) {
        self.ring = ring
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.collect() }
        timer.resume()
    }

    private func collect() {
        let written = ring.totalWritten
        let count = Int(written - collectedUpTo)
        guard count > 0 else { return }
        var chunk = [Float](repeating: 0, count: count)
        let fine = chunk.withUnsafeMutableBufferPointer {
            ring.read(endingAt: written, count: count, into: $0.baseAddress!)
        }
        if fine { heard += chunk } else { missedSome = true }
        collectedUpTo = written
    }

    /// Stops collecting. Returns nil if the ring was written over before it was read.
    func finish() -> [Float]? {
        queue.sync {
            timer.cancel()
            collect()
            return missedSome ? nil : heard
        }
    }
}

/// Lets a moment pass, on the main thread's own timer.
///
/// `Task.sleep` isn't used: its timers share a few threads with every other test, and
/// while those are busy measuring sound, a sleep of a fiftieth of a second was seen to
/// last six seconds. Tests that play in real time can't afford that.
@MainActor
func pause(seconds: Double) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { continuation.resume() }
    }
}

/// Waits until this test run isn't too busy to keep time. Call it at the start of any
/// test that plays sound in real time.
///
/// All the tests start together, and for the first several seconds the ones that
/// measure long stretches of sound keep every worker thread busy. Until they finish,
/// macOS can't deliver timers or a player's callbacks on time (stalls of six seconds
/// were measured), and a test that plays three seconds of sound would miss all of it.
@MainActor
func waitForAQuietMoment() async {
    var onTime = 0
    let deadline = Date().addingTimeInterval(120)
    while onTime < 15, Date() < deadline {
        let before = Date()
        await pause(seconds: 0.02)
        onTime = Date().timeIntervalSince(before) < 0.06 ? onTime + 1 : 0
    }
}

/// Waits, checking fifty times a second, until `done` says so or the time runs out.
@MainActor
func wait(upTo seconds: Double, until done: () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while !done(), Date() < deadline {
        await pause(seconds: 0.02)
    }
}
