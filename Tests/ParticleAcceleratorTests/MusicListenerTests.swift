import AVFoundation
import Testing

@testable import ParticleAccelerator

/// Runs a test with a folder of its own, removed afterwards.
private func withTemporaryFolder(_ body: (URL) throws -> Void) throws {
    let folder = try TemporaryFolder()
    try body(folder.url)
}

/// Writes a short tone as a sound file.
private func writeTone(to url: URL, seconds: Double) throws {
    let sound = TestSound.sine(hz: 440, amplitude: 0.5, seconds: seconds)
    try writeSoundFile(left: sound, right: sound, sampleRate: TestSound.sampleRate, to: url)
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

/// The one test that really plays a file. It plays it muted, so it makes no sound.
@MainActor
@Test(.enabled(if: macHasSoundOutput, "This computer has no sound output to play through."))
func whatTheAnalyserHearsIsExactlyTheFileEvenWhenMuted() async throws {
    await waitForAQuietMoment()
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
    await wait(upTo: 30) { stoppedByItself }
    #expect(stoppedByItself)
    #expect(playback.isPlaying == false)
    #expect(playback.currentTime == 0)

    // Silence keeps arriving for a moment after the song ends, so the visuals settle
    // instead of freezing on the last note.
    let writtenAtTheEnd = playback.ring.totalWritten
    await pause(seconds: 0.4)
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
