import Foundation

/// A made-up song for checking the listener against facts that are known exactly,
/// because the song is built from them: its tempo, the moment every kick lands, the
/// notes the bass plays.
///
/// It's 40 seconds of a simple dance beat at 124 beats a minute:
/// - a kick drum on every beat
/// - a snare on beats 2 and 4
/// - a hi-hat and a bass note halfway between the beats
/// - a soft chord held through each bar
///
/// The tests listen to it (MadeUpSongTests.swift), and `scripts/make_test_song.sh`
/// writes it to a sound file for trying in the app. This file uses only Foundation, so
/// the script can build it by itself.
enum TestSong {
    static let sampleRate = 44_100.0
    static let beatsPerMinute = 124.0
    static let seconds = 40.0
    static let beatSeconds = 60 / beatsPerMinute
    /// 82 beats fit in the 40 seconds.
    static let beatCount = Int(seconds / beatSeconds)
    /// The moment each kick lands, in seconds.
    static let kickTimes: [Double] = (0..<beatCount).map { Double($0) * beatSeconds }
    /// The loudest sample in the song. Full volume is 1, so this is 14 decibels below.
    static let loudestSample = 0.2
    /// The bass note of each bar, in Hz. The four bars repeat: A, A, C, G.
    static let bassNotes = [55.0, 55.0, 65.4, 49.0]
    /// The chord of each bar, in Hz: A minor, A minor, C major, G major.
    static let chords = [
        [220.0, 261.6, 329.6], [220.0, 261.6, 329.6], [261.6, 329.6, 392.0], [196.0, 246.9, 293.7],
    ]

    static func samples() -> [Float] {
        var song = [Double](repeating: 0, count: Int(seconds * sampleRate))
        // The same "random" hiss every time, so the song never changes.
        var hissState: UInt64 = 7
        func hiss() -> Double {
            hissState = hissState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(hissState >> 40) / Double(1 << 24) * 2 - 1
        }
        /// Adds a sound that starts at `start` seconds and lasts `length`. `wave` gives
        /// its value at each moment after its start.
        func add(at start: Double, length: Double, _ wave: (Double) -> Double) {
            let first = Int(start * sampleRate)
            for offset in 0..<Int(length * sampleRate) where first + offset < song.count {
                song[first + offset] += wave(Double(offset) / sampleRate)
            }
        }
        let turn = 2 * Double.pi

        for beat in 0..<beatCount {
            let start = kickTimes[beat]
            let bar = (beat / 4) % 4

            // The kick: a thump whose pitch drops from 120 to 50 Hz.
            add(at: start, length: 0.28) { time in
                0.9 * sin(turn * (50 * time + 70 * 0.04 * (1 - exp(-time / 0.04)))) * exp(-time / 0.07)
            }
            if beat % 4 == 1 || beat % 4 == 3 {
                // The snare: a burst of hiss with a short tone in it.
                add(at: start, length: 0.18) { time in
                    0.35 * hiss() * exp(-time / 0.05) + 0.25 * sin(turn * 190 * time) * exp(-time / 0.04)
                }
            }
            add(at: start + beatSeconds / 2, length: 0.05) { time in
                0.18 * hiss() * exp(-time / 0.012)
            }
            let bassNote = bassNotes[bar]
            add(at: start + beatSeconds / 2, length: beatSeconds * 0.45) { time in
                0.45 * sin(turn * bassNote * time) * min(1, time / 0.01) * exp(-time / 0.25)
            }
            if beat % 4 == 0 {
                for note in chords[bar] {
                    add(at: start, length: beatSeconds * 4) { time in
                        0.07 * (sin(turn * note * time) + 0.4 * sin(2 * turn * note * time))
                            * min(1, time / 0.3) * exp(-time / 1.5)
                    }
                }
            }
        }

        let loudest = song.reduce(0) { max($0, abs($1)) }
        let gain = loudestSample / loudest
        return song.map { Float($0 * gain) }
    }
}
