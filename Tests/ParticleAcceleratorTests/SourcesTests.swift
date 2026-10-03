import AVFoundation
import CoreAudio
import Testing

@testable import ParticleAccelerator

// The Mac's own sound and the microphone need the person's permission, so no test
// starts them. These check the parts around them.

@Test func theAnalyserStopsAtTheSoundThatHasBeenHeard() {
    let listener = TestListener()
    // Two seconds are in the ring, a low tone then a high one, but only the first
    // second has reached the speakers.
    let sound = TestSound.sine(hz: 300, amplitude: 0.5, seconds: 1)
        + TestSound.sine(hz: 3_000, amplitude: 0.5, seconds: 1)
    sound.withUnsafeBufferPointer { pointer in
        var written = 0
        while written < sound.count {
            let count = min(512, sound.count - written)
            listener.ring.write(pointer.baseAddress! + written, count: count)
            written += count
        }
    }
    let heardSoFar = listener.analyser.update(upTo: 44_100 - 4_096)
    #expect(abs(heardSoFar.seconds - 0.9) < 0.02)
    #expect(heardSoFar.bandDecibels.lowMids > heardSoFar.bandDecibels.vocals + 20)

    // A limit that goes backwards (a player seeking back) measures nothing new.
    let unchanged = listener.analyser.update(upTo: 10_000)
    #expect(unchanged == heardSoFar)

    let all = listener.analyser.update()
    #expect(abs(all.seconds - 2) < 0.02)
    #expect(all.bandDecibels.vocals > all.bandDecibels.lowMids + 20)
}

@Test func aQuietedReadingKeepsTheBeatButNotTheSound() {
    var reading = SoundReading.silence
    reading.bars[3] = 0.7
    reading.bands.kick = 0.9
    reading.loudness = 0.8
    reading.beat = 1
    reading.beatsHeard = 12
    reading.beatsPerMinute = 124
    reading.beatPhase = 0.4
    reading.steadyBeats = 30
    reading.seconds = 15

    let quiet = reading.quieted
    #expect(quiet.bars == SIMD64<Float>(repeating: 0))
    #expect(quiet.bands == BandValues())
    #expect(quiet.loudness == 0)
    #expect(quiet.beat == 0)
    #expect(quiet.beatsHeard == 12)
    #expect(quiet.beatsPerMinute == 124)
    #expect(quiet.beatPhase == 0.4)
    #expect(quiet.steadyBeats == 30)
    #expect(quiet.seconds == 15)
}

@Test func aBuffersLengthIsCountedInSamplesPerChannel() {
    // 512 samples of left and right together, each a 4-byte number.
    let stereo = AudioBuffer(mNumberChannels: 2, mDataByteSize: 512 * 2 * 4, mData: nil)
    #expect(DeviceListening.frameCount(of: stereo) == 512)
    let mono = AudioBuffer(mNumberChannels: 1, mDataByteSize: 480 * 4, mData: nil)
    #expect(DeviceListening.frameCount(of: mono) == 480)
    let empty = AudioBuffer(mNumberChannels: 0, mDataByteSize: 64, mData: nil)
    #expect(DeviceListening.frameCount(of: empty) == 0)
}

@Test func onlyTheUsualSoundFormatIsAccepted() throws {
    let usual = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
    #expect(DeviceListening.isUsualFormat(usual.streamDescription.pointee))
    let whole = try #require(
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2, interleaved: true))
    #expect(DeviceListening.isUsualFormat(whole.streamDescription.pointee) == false)
}

@Test(.enabled(if: macHasSoundOutput, "This computer has no sound output to ask about."))
func theMacsOutputSaysHowLongItTakesToPlay() throws {
    let output = try #require(SoundDevices.defaultOutput)
    #expect(SoundDevices.name(of: output)?.isEmpty == false)
    #expect((SoundDevices.sampleRate(of: output) ?? 0) >= 8_000)
    // Some delay, and never more than a second.
    let delay = SoundDevices.outputDelaySeconds()
    #expect(delay > 0 && delay <= 1)
}

@MainActor @Test func theTimingOffsetStaysWithinHalfASecond() {
    let listener = MusicListener()
    #expect(listener.timingOffset == 0)
    listener.timingOffset = 0.12
    #expect(listener.timingOffset == 0.12)
    listener.timingOffset = 3
    #expect(listener.timingOffset == 0.5)
    listener.timingOffset = -3
    #expect(listener.timingOffset == -0.5)
}

@MainActor @Test func theListenerSaysWhatItIsListeningTo() throws {
    let folder = try TemporaryFolder()
    let url = folder.file("A Song.caf")
    let sound = TestSound.sine(hz: 440, amplitude: 0.5, seconds: 1)
    try writeSoundFile(left: sound, right: sound, sampleRate: 44_100, to: url)

    let listener = MusicListener()
    #expect(listener.source == .nothing)
    #expect(listener.sourceName == nil)

    try listener.load(songFile: url)
    #expect(listener.source == .songFile)
    #expect(listener.sourceName == "A Song")

    // Handing it a player stops the song file.
    listener.listen(to: AVPlayer())
    #expect(listener.source == .player)
    #expect(listener.songTitle == nil)
    #expect(listener.duration == 0)

    listener.stop()
    #expect(listener.source == .nothing)
    #expect(listener.problem == nil)
}

@MainActor @Test func aSongFilesReadingsWaitForTheSpeakers() {
    // What the file player has copied is ahead of what's been heard by the output's
    // delay: the listener only measures up to what's been heard.
    let ring = SampleRing(sampleRate: 44_100)
    let analyser = SoundAnalyser(ring: ring)
    let sound = TestSound.sine(hz: 440, amplitude: 0.5, seconds: 1)
    sound.withUnsafeBufferPointer { pointer in
        var written = 0
        while written < sound.count {
            ring.write(pointer.baseAddress! + written, count: min(512, sound.count - written))
            written += 512
        }
    }
    // A fifth of a second of delay, as Bluetooth headphones have.
    let delay = Int64(0.2 * 44_100)
    let reading = analyser.update(upTo: ring.totalWritten - delay)
    #expect(abs(reading.seconds - 0.8) < 0.02)
}

@Test func theChosenInputIsUsedWhenItIsAnOrdinaryOne() throws {
    let choice = try MicrophoneFeed.choose(
        chosen: (device: 7, name: "USB Turntable", isBluetooth: false),
        builtIn: (device: 3, name: "iMac Microphone"))
    #expect(choice == MicrophoneFeed.InputChoice(device: 7, name: "USB Turntable", note: nil))
}

@Test func aBluetoothHeadsetIsPassedOverForTheMacsOwnMicrophone() throws {
    // Listening to the headset would switch it to call quality and spoil the music.
    let choice = try MicrophoneFeed.choose(
        chosen: (device: 9, name: "Headphones", isBluetooth: true),
        builtIn: (device: 3, name: "iMac Microphone"))
    #expect(choice.device == 3)
    #expect(choice.name == "iMac Microphone")
    #expect(choice.note?.contains("“Headphones”, is a Bluetooth headset") == true)
}

@Test func aBluetoothHeadsetOnAMacWithNoMicrophoneIsRefusedPlainly() {
    let error = #expect(throws: ListeningProblem.self) {
        try MicrophoneFeed.choose(chosen: (device: 9, name: "Headphones", isBluetooth: true), builtIn: nil)
    }
    #expect(error?.message.contains("call quality") == true)
    #expect(error?.message.contains("System Settings → Sound → Input") == true)
}

@Test func noInputAtAllIsSaidPlainly() {
    let error = #expect(throws: ListeningProblem.self) {
        try MicrophoneFeed.choose(chosen: nil, builtIn: nil)
    }
    #expect(error?.message.contains("no microphone or line input") == true)
}
