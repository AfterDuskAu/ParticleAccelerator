import Foundation
import Testing

@testable import ParticleAccelerator

/// When each beat was heard, in seconds.
private func beatTimes(in sound: [Float]) -> [Double] {
    var times: [Double] = []
    var heard = 0
    TestListener().hear(sound) { reading in
        if reading.beatsHeard > heard {
            heard = reading.beatsHeard
            times.append(reading.seconds)
        }
    }
    return times
}

@Test(arguments: [90.0, 120.0, 140.0, 174.0])
func everyKickIsHeardOnceAndOnTime(beatsPerMinute: Double) {
    let times = beatTimes(in: TestSound.kicks(beatsPerMinute: beatsPerMinute, seconds: 10))
    let beatLength = 60 / beatsPerMinute
    let kicksPlayed = Int((10 / beatLength).rounded(.up))
    #expect(times.count == kicksPlayed)
    for (number, time) in times.enumerated() {
        // Heard within 50 thousandths of a second of when it was played.
        let played = Double(number) * beatLength
        #expect(time - played > 0 && time - played < 0.05, "beat \(number) at \(time)")
    }
}

@Test(arguments: [70.0, 90.0, 120.0, 128.0, 140.0, 174.0])
func theTempoOfASteadyKickIsFound(beatsPerMinute: Double) throws {
    let reading = TestListener().hear(TestSound.kicks(beatsPerMinute: beatsPerMinute, seconds: 12))
    let found = try #require(reading.beatsPerMinute)
    #expect(abs(found - beatsPerMinute) < 1.5, "found \(found)")
}

@Test func aQuietSongsKicksAreHeardToo() {
    let times = beatTimes(in: TestSound.kicks(beatsPerMinute: 120, seconds: 6, amplitude: 0.01))
    #expect(times.count == 12)
}

@Test func theBeatPulseJumpsOnTheKickAndFadesBeforeTheNext() {
    var strongest: Float = 0
    var weakestBetweenKicks: Float = 1
    TestListener().hear(TestSound.kicks(beatsPerMinute: 120, seconds: 6)) { reading in
        guard reading.seconds > 2 else { return }
        strongest = max(strongest, reading.beat)
        let sinceKick = reading.seconds.truncatingRemainder(dividingBy: 0.5)
        if sinceKick > 0.3 { weakestBetweenKicks = min(weakestBetweenKicks, reading.beat) }
    }
    #expect(strongest > 0.8)
    #expect(weakestBetweenKicks < 0.05)
}

@Test func theSteadyCountStaysInStepWithTheKicks() {
    var heard = 0
    var furthestOff = 0.0
    var countAtTenSeconds = 0
    let reading = TestListener().hear(TestSound.kicks(beatsPerMinute: 120, seconds: 20)) { reading in
        if reading.seconds <= 10 { countAtTenSeconds = reading.steadyBeats }
        guard reading.beatsHeard > heard else { return }
        heard = reading.beatsHeard
        // Once it has settled, each kick should land where the count turns over.
        if reading.seconds > 8 {
            furthestOff = max(furthestOff, min(reading.beatPhase, 1 - reading.beatPhase))
        }
    }
    #expect(furthestOff < 0.1)
    // Ten seconds at 120 beats a minute is 20 beats.
    #expect(reading.steadyBeats - countAtTenSeconds == 20)
}

@Test func theSteadyCountCarriesOnWhenTheDrumsDropOut() {
    let listener = TestListener()
    listener.hear(TestSound.kicks(beatsPerMinute: 120, seconds: 10))
    let before = listener.analyser.reading.steadyBeats
    // Two seconds with a held note and no drums: four more beats at 120.
    let after = listener.hear(TestSound.sine(hz: 440, amplitude: 0.3, seconds: 2))
    #expect(after.steadyBeats - before == 4)
    #expect(after.beatsPerMinute != nil)
}

@Test func aNewTempoIsFollowed() throws {
    let listener = TestListener()
    listener.hear(TestSound.kicks(beatsPerMinute: 100, seconds: 10))
    let reading = listener.hear(TestSound.kicks(beatsPerMinute: 132, seconds: 14))
    let found = try #require(reading.beatsPerMinute)
    #expect(abs(found - 132) < 1.5, "found \(found)")
}

@Test func hissHasNoTempo() {
    let reading = TestListener().hear(TestSound.noise(amplitude: 0.3, seconds: 12))
    #expect(reading.beatsPerMinute == nil)
}

@Test func aHeldNoteHasNoBeats() {
    let times = beatTimes(in: TestSound.sine(hz: 100, amplitude: 0.5, seconds: 5))
    // The note starting is one jump; holding it is none.
    #expect(times.count <= 1)
}

@Test func bassNotesBetweenTheKicksArentCountedAsBeats() {
    let times = beatTimes(in: TestSound.band(beatsPerMinute: 120, seconds: 10))
    // 20 kicks in ten seconds, with a bass note after each.
    #expect(times.count == 20)
}

@Test(arguments: [96.0, 124.0, 150.0])
func aSnareOnEveryOtherBeatDoesntHalveTheTempo(beatsPerMinute: Double) throws {
    let reading = TestListener().hear(TestSound.band(beatsPerMinute: beatsPerMinute, seconds: 12))
    let found = try #require(reading.beatsPerMinute)
    #expect(abs(found - beatsPerMinute) < 1.5, "found \(found)")
}

@Test func theTempoIsKeptThroughAPassageWithNoRhythm() throws {
    let listener = TestListener()
    listener.hear(TestSound.band(beatsPerMinute: 124, seconds: 10))
    // Six seconds of a held chord: no beats to measure, but the count carries on.
    let chord = zip(TestSound.sine(hz: 220, amplitude: 0.2, seconds: 6), TestSound.sine(hz: 330, amplitude: 0.2, seconds: 6)).map(+)
    let reading = listener.hear(chord)
    let kept = try #require(reading.beatsPerMinute)
    #expect(abs(kept - 124) < 1.5)
}

@Test func theTempoIsForgottenAfterLongSilence() {
    let listener = TestListener()
    listener.hear(TestSound.kicks(beatsPerMinute: 120, seconds: 10))
    let stillKnown = listener.hear(TestSound.silence(seconds: 5))
    #expect(stillKnown.beatsPerMinute != nil)
    let reading = listener.hear(TestSound.silence(seconds: 6))
    #expect(reading.beatsPerMinute == nil)
}

@Test func soundTooFaintToBeMusicHasNoBeatsAndNoTempo() {
    // Kicks 70 decibels below full volume: what a microphone hears of headphones
    // across a quiet room.
    let faint = TestSound.kicks(beatsPerMinute: 120, seconds: 12, amplitude: 0.0003)
    let reading = TestListener().hear(faint)
    #expect(reading.beatsHeard == 0)
    #expect(reading.beatsPerMinute == nil)
}
