import AVFoundation
import CoreAudio
import Testing

@testable import ParticleAccelerator

/// A folder of the test's own in the Mac's temporary place, removed afterwards.
private func withTemporaryFolder(_ body: (URL) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ParticleAcceleratorTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(folder)
}

/// Writes a short tone as a sound file. It's only ever opened, never played, so the
/// tests make no sound.
private func writeTone(to url: URL, seconds: Double) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
    let frames = AVAudioFrameCount(seconds * 44_100)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    let tone = TestSound.sine(hz: 440, amplitude: 0.5, seconds: seconds)
    let channels = try #require(buffer.floatChannelData)
    for channel in 0..<2 {
        for frame in 0..<Int(frames) { channels[channel][frame] = tone[frame] }
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}

@MainActor @Test func aSongFileOpensWithItsNameAndLength() throws {
    try withTemporaryFolder { folder in
        let url = folder.appendingPathComponent("Test Tone.caf")
        try writeTone(to: url, seconds: 2)

        let listener = MusicListener()
        try listener.load(songFile: url)
        #expect(listener.songTitle == "Test Tone")
        #expect(abs(listener.duration - 2) < 0.01)
        #expect(listener.isPlaying == false)
        #expect(listener.currentTime == 0)
        // Nothing has played, so there's nothing to hear yet.
        #expect(listener.reading() == .silence)

        listener.seek(to: 1.5)
        #expect(abs(listener.currentTime - 1.5) < 0.001)
        listener.seek(to: 99)
        #expect(listener.currentTime <= listener.duration)

        listener.stop()
        #expect(listener.songTitle == nil)
        #expect(listener.duration == 0)
    }
}

@MainActor @Test func aFileThatIsntSoundIsRefusedInPlainEnglish() throws {
    try withTemporaryFolder { folder in
        let url = folder.appendingPathComponent("Not a song.mp3")
        try "just some words".write(to: url, atomically: true, encoding: .utf8)

        let listener = MusicListener()
        let error = #expect(throws: ListeningProblem.self) {
            try listener.play(songFile: url)
        }
        #expect(error?.localizedDescription.contains("“Not a song.mp3” can't be played") == true)
        #expect(listener.songTitle == nil)
        #expect(listener.isPlaying == false)
    }
}

@MainActor @Test func aMissingFileIsRefusedInPlainEnglish() {
    let listener = MusicListener()
    let url = URL(fileURLWithPath: "/nowhere/Gone.wav")
    #expect(throws: ListeningProblem.self) {
        try listener.play(songFile: url)
    }
}

@MainActor @Test func aSongThatFailsToOpenLeavesTheOneAlreadyLoaded() throws {
    try withTemporaryFolder { folder in
        let good = folder.appendingPathComponent("Good.caf")
        try writeTone(to: good, seconds: 1)
        let bad = folder.appendingPathComponent("Bad.wav")
        try "no sound here".write(to: bad, atomically: true, encoding: .utf8)

        let listener = MusicListener()
        try listener.load(songFile: good)
        #expect(throws: ListeningProblem.self) { try listener.load(songFile: bad) }
        #expect(listener.songTitle == "Good")
    }
}

@MainActor @Test func muteIsRememberedFromOneSongToTheNext() throws {
    try withTemporaryFolder { folder in
        let first = folder.appendingPathComponent("First.caf")
        let second = folder.appendingPathComponent("Second.caf")
        try writeTone(to: first, seconds: 1)
        try writeTone(to: second, seconds: 1)

        let listener = MusicListener()
        #expect(listener.isMuted == false)
        listener.isMuted = true
        try listener.load(songFile: first)
        try listener.load(songFile: second)
        #expect(listener.isMuted == true)
    }
}

/// Some CI machines have no sound output at all. This asks Core Audio which device
/// sound goes to, without starting anything.
private let macHasSoundOutput: Bool = {
    var device = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
    return status == noErr && device != kAudioObjectUnknown
}()

/// Collects everything a ring hears, on a thread of its own, the way an analyser would.
private final class RingRecorder: @unchecked Sendable {
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

/// The one test that really plays a file. It plays it muted, so it makes no sound.
@MainActor
@Test(.enabled(if: macHasSoundOutput, "This computer has no sound output to play through."))
func whatTheAnalyserHearsIsExactlyTheFileEvenWhenMuted() async throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ParticleAcceleratorTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    // Half a second with different sound left and right, at a sample rate the Mac's
    // output probably isn't using, to show the copy is taken before any conversion.
    let rate = 48_000.0
    let frames = 24_000
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
    buffer.frameLength = AVAudioFrameCount(frames)
    let channels = try #require(buffer.floatChannelData)
    var expected = [Float](repeating: 0, count: frames)
    for frame in 0..<frames {
        let time = Double(frame) / rate
        channels[0][frame] = Float(0.5 * cos(2 * Double.pi * 440 * time))
        channels[1][frame] = Float(0.25 * cos(2 * Double.pi * 660 * time))
        expected[frame] = (channels[0][frame] + channels[1][frame]) * 0.5
    }
    let url = folder.appendingPathComponent("Half a second.caf")
    do {
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    let playback = try SongFilePlayback(url: url)
    #expect(playback.ring.sampleRate == rate)
    let recorder = RingRecorder(ring: playback.ring)
    var stoppedByItself = false
    playback.onStopped = { stoppedByItself = true }
    playback.isMuted = true
    try playback.play()
    #expect(playback.isPlaying)
    for _ in 0..<500 where !stoppedByItself {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(stoppedByItself)
    #expect(playback.isPlaying == false)
    #expect(playback.currentTime == 0)

    // Silence keeps arriving for a moment after the song ends, so the visuals settle
    // instead of freezing on the last note.
    let writtenAtTheEnd = playback.ring.totalWritten
    try await Task.sleep(for: .milliseconds(400))
    #expect(playback.ring.totalWritten - writtenAtTheEnd > Int64(rate * 0.1))
    playback.shutDown()

    // Find the song in what the ring heard, and compare it sample for sample.
    let heard = try #require(recorder.finish())
    let start = try #require(heard.firstIndex { $0 != 0 })
    try #require(start + frames <= heard.count)
    #expect(Array(heard[start..<(start + frames)]) == expected)
}

@Test func timesReadLikeAClock() {
    #expect(SoundCheckView.clock(0) == "0:00")
    #expect(SoundCheckView.clock(83.9) == "1:23")
    #expect(SoundCheckView.clock(600) == "10:00")
}

@Test func bandPitchesReadPlainly() {
    #expect(SoundCheckView.pitches(of: .kick) == "60–150 Hz")
    #expect(SoundCheckView.pitches(of: .mids) == "500 Hz–2 kHz")
    #expect(SoundCheckView.pitches(of: .vocals) == "2–6 kHz")
}
