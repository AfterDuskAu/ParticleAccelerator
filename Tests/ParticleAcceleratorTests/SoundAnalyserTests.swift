import Foundation
import Testing

@testable import ParticleAccelerator

/// The bar that covers a pitch.
private func bar(for hz: Float) -> Int {
    let ratio = SoundAnalyser.highestBarHz / SoundAnalyser.lowestBarHz
    return Int(Float(SoundAnalyser.barCount) * log(hz / SoundAnalyser.lowestBarHz) / log(ratio))
}

private func loudestBar(_ reading: SoundReading) -> Int {
    (0..<SoundAnalyser.barCount).max { reading.bars[$0] < reading.bars[$1] } ?? 0
}

@Test func silenceReadsAsNothing() {
    let reading = TestListener().hear(TestSound.silence(seconds: 2))
    #expect(reading.bars == SIMD64<Float>(repeating: 0))
    #expect(reading.bands == BandValues())
    #expect(reading.loudness == 0)
    #expect(reading.beatsHeard == 0)
    #expect(reading.beatsPerMinute == nil)
    #expect(abs(reading.seconds - 2) < 0.02)
}

@Test(arguments: [
    (Band.sub, 40.0), (.kick, 100.0), (.lowMids, 300.0), (.mids, 1_000.0), (.vocals, 4_000.0),
    (.air, 10_000.0),
])
func aToneLandsInItsOwnBand(band: Band, hz: Double) {
    let reading = TestListener().hear(TestSound.sine(hz: hz, amplitude: 0.5, seconds: 1))
    // Half volume is 6 decibels below full.
    #expect(abs(reading.bandDecibels[band] - -6) < 1.5)
    #expect(reading.bands[band] > 0.95)
    for other in Band.allCases where other != band {
        #expect(reading.bandDecibels[other] < reading.bandDecibels[band] - 6)
    }
}

@Test(arguments: [100.0, 440.0, 1_000.0, 5_000.0, 12_000.0])
func aToneRaisesTheBarAtItsPitch(hz: Double) {
    let reading = TestListener().hear(TestSound.sine(hz: hz, amplitude: 0.5, seconds: 1))
    let expected = bar(for: Float(hz))
    #expect(abs(loudestBar(reading) - expected) <= 1)
    #expect(reading.bars[loudestBar(reading)] > 0.95)
}

@Test func bassIsOnTheLeftAndHighsAreOnTheRight() {
    let bass = TestListener().hear(TestSound.sine(hz: 60, amplitude: 0.5, seconds: 1))
    let highs = TestListener().hear(TestSound.sine(hz: 8_000, amplitude: 0.5, seconds: 1))
    #expect(loudestBar(bass) < 12)
    #expect(loudestBar(highs) > 50)
}

@Test func loudnessIsMeasuredInDecibels() {
    // A sine wave at half volume has an average strength of 0.354, which is -9 decibels.
    let reading = TestListener().hear(TestSound.sine(hz: 440, amplitude: 0.5, seconds: 1))
    #expect(abs(reading.loudnessDecibels - -9.03) < 0.3)
    #expect(reading.loudness > 0.95)
}

@Test func hissLightsEveryBandAndBar() {
    let reading = TestListener().hear(TestSound.noise(amplitude: 0.3, seconds: 2))
    for band in Band.allCases {
        #expect(reading.bands[band] > 0.5)
    }
    for index in 0..<SoundAnalyser.barCount {
        #expect(reading.bars[index] > 0.1)
    }
}

@Test func aQuietSongMovesAsMuchAsALoudOne() {
    let quiet = TestListener().hear(TestSound.sine(hz: 100, amplitude: 0.02, seconds: 3))
    let loud = TestListener().hear(TestSound.sine(hz: 100, amplitude: 0.8, seconds: 3))
    #expect(quiet.bands.kick > 0.95)
    #expect(loud.bands.kick > 0.95)
    #expect(quiet.bandDecibels.kick < loud.bandDecibels.kick - 30)
}

@Test func aQuietVerseAfterALoudPartReadsLowerThenRecovers() {
    let listener = TestListener()
    listener.hear(TestSound.sine(hz: 100, amplitude: 0.8, seconds: 4))

    // 10 decibels quieter: half of the 20-decibel range, so about 0.5.
    let verse = TestSound.sine(hz: 100, amplitude: 0.253, seconds: 16)
    var soonAfter: Float = -1
    let muchLater = listener.hear(verse) { reading in
        if soonAfter < 0, reading.seconds > 4.5 { soonAfter = reading.bands.kick }
    }
    #expect(soonAfter > 0.4 && soonAfter < 0.6)
    #expect(muchLater.bands.kick > 0.9)
}

@Test func hissFarBelowTheMusicIsNotTurnedUp() {
    // A loud bass note with very faint hiss: the highs have almost nothing in them and
    // should stay near 0 instead of being auto-gained up to full.
    let bass = TestSound.sine(hz: 100, amplitude: 0.8, seconds: 3)
    let hiss = TestSound.noise(amplitude: 0.0005, seconds: 3)
    let reading = TestListener().hear(zip(bass, hiss).map(+))
    #expect(reading.bands.kick > 0.95)
    #expect(reading.bands.air < 0.2)
}

@Test func readingsDontDependOnHowOftenFramesCome() {
    let sound = TestSound.kicks(beatsPerMinute: 120, seconds: 3)
    let everyAudioChunk = TestListener().hear(sound, chunk: 512)
    let at60FramesASecond = TestListener().hear(sound, chunk: 735)
    let at24FramesASecond = TestListener().hear(sound, chunk: 1_837)
    // Each has measured up to its own last whole step: compare them at the same moment.
    #expect(everyAudioChunk.seconds == at60FramesASecond.seconds)
    #expect(everyAudioChunk == at60FramesASecond)
    #expect(everyAudioChunk == at24FramesASecond)
}

@Test func afterFallingFarBehindItSkipsToTheNewestSound() {
    let listener = TestListener()
    // Four seconds arrive with no frame asking for a reading (the window was hidden).
    let sound = TestSound.sine(hz: 1_000, amplitude: 0.5, seconds: 4)
    var written = 0
    while written < sound.count {
        let count = min(512, sound.count - written)
        sound.withUnsafeBufferPointer { listener.ring.write($0.baseAddress! + written, count: count) }
        written += count
    }
    let reading = listener.analyser.update()
    #expect(abs(reading.seconds - 4) < 0.02)
    #expect(reading.bands.mids > 0.95)
}

@Test func aLowQualityFilesMissingHighsReadAsNothing() {
    // Sound at 16,000 samples a second can't hold pitches above 8 kHz.
    let ring = SampleRing(sampleRate: 16_000)
    let analyser = SoundAnalyser(ring: ring)
    let hiss = TestSound.noise(amplitude: 0.3, seconds: 1)
    var written = 0
    while written < 16_000 {
        hiss.withUnsafeBufferPointer { ring.write($0.baseAddress! + written, count: 500) }
        written += 500
        _ = analyser.update()
    }
    let reading = analyser.update()
    #expect(reading.bars[40] > 0.2)
    // The top bars start above 8 kHz.
    for index in 58..<SoundAnalyser.barCount {
        #expect(reading.bars[index] == 0)
    }
}

@Test func soundAtHighSampleRatesIsMeasuredOverTheSameLengthOfTime() {
    let ordinary = SoundAnalyser(ring: SampleRing(sampleRate: 44_100))
    let high = SoundAnalyser(ring: SampleRing(sampleRate: 96_000))
    #expect(ordinary.windowSize == 2_048)
    #expect(ordinary.stepSize == 512)
    #expect(high.windowSize == 4_096)
    #expect(abs(ordinary.stepSeconds - high.stepSeconds) < 0.002)
}
