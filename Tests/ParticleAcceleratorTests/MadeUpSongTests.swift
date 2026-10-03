import Foundation
import Testing

@testable import ParticleAccelerator

/// What the listener made of the made-up song, gathered in one pass and shared by the
/// tests below.
private struct Heard {
    /// The moment each beat was heard, in seconds.
    var beatTimes: [Double] = []
    /// The tempo, the steady count and the kick band's level at every reading.
    var moments: [(seconds: Double, tempo: Double?, steadyBeats: Int, kick: Float)] = []
    var loudestDecibels: Float = SoundReading.silenceDecibels
}

private let heard: Heard = {
    var heard = Heard()
    var beats = 0
    TestListener().hear(TestSong.samples()) { reading in
        if reading.beatsHeard > beats {
            beats = reading.beatsHeard
            heard.beatTimes.append(reading.seconds)
        }
        heard.moments.append((reading.seconds, reading.beatsPerMinute, reading.steadyBeats, reading.bands.kick))
        heard.loudestDecibels = max(heard.loudestDecibels, reading.loudnessDecibels)
    }
    return heard
}()

@Test func theMadeUpSongIsBuiltAsDescribed() {
    let song = TestSong.samples()
    #expect(song.count == 1_764_000)
    #expect(TestSong.kickTimes.count == 82)
    let loudest = song.reduce(Float(0)) { max($0, abs($1)) }
    #expect(abs(loudest - 0.2) < 0.0001)
}

@Test func itsTempoIsFoundAndHeld() throws {
    // 124 beats a minute. Found within eight seconds, and never lost or changed after.
    let settled = heard.moments.filter { $0.seconds > 8 }
    #expect(!settled.isEmpty)
    for moment in settled {
        let tempo = try #require(moment.tempo, "no tempo at \(moment.seconds) s")
        #expect(abs(tempo - TestSong.beatsPerMinute) < 1, "\(tempo) at \(moment.seconds) s")
    }
}

@Test func everyOneOfItsKicksIsHeardOnTimeAndNothingElseIs() {
    // 82 kicks. The bass notes, snares and hi-hats between them aren't beats.
    #expect(heard.beatTimes.count == TestSong.kickTimes.count)
    for (heardAt, playedAt) in zip(heard.beatTimes, TestSong.kickTimes) {
        // Heard within 50 thousandths of a second of when it was played.
        #expect(heardAt - playedAt > 0 && heardAt - playedAt < 0.05, "kick at \(playedAt) heard at \(heardAt)")
    }
}

@Test func theSteadyCountKeepsItsTime() throws {
    // From 10 to 38 seconds is 28 seconds: 57.9 beats at 124 a minute.
    let at10 = try #require(heard.moments.last { $0.seconds <= 10 })
    let at38 = try #require(heard.moments.last { $0.seconds <= 38 })
    let counted = at38.steadyBeats - at10.steadyBeats
    #expect(counted == 57 || counted == 58)
}

@Test func theKickBandJumpsOnEachKickAndFallsBackBeforeTheNext() {
    // Just after a kick the band is near its peak. A fifth of a second later the kick
    // has died away, and the bass note hasn't started yet.
    func kickLevel(_ secondsAfterKick: Double, kick: Int) -> Float {
        let time = TestSong.kickTimes[kick] + secondsAfterKick
        return heard.moments.last { $0.seconds <= time }?.kick ?? 0
    }
    for kick in 20..<70 {
        #expect(kickLevel(0.05, kick: kick) > 0.8, "kick \(kick)")
        #expect(kickLevel(0.21, kick: kick) < 0.5, "kick \(kick)")
    }
}

@Test func itsLoudnessIsMeasuredTruly() {
    // No stretch of the song can be louder than its loudest sample, 0.2, which is 14
    // decibels below full volume; and its kicks come within a few decibels of that.
    #expect(heard.loudestDecibels < -14)
    #expect(heard.loudestDecibels > -24)
}
