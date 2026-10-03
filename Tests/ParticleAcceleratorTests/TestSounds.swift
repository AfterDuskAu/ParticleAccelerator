import Foundation

@testable import ParticleAccelerator

/// Sound made while the tests run: no audio files are committed, and none of the
/// owner's music is used.
enum TestSound {
    static let sampleRate = 44_100.0

    /// A pure tone at one pitch.
    static func sine(hz: Double, amplitude: Float, seconds: Double) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { index in
            amplitude * Float(sin(2 * Double.pi * hz * Double(index) / sampleRate))
        }
    }

    static func silence(seconds: Double) -> [Float] {
        Array(repeating: 0, count: Int(seconds * sampleRate))
    }

    /// Hiss with every pitch in it. The same seed always gives the same hiss, so a test
    /// that passes once passes every time.
    static func noise(amplitude: Float, seconds: Double, seed: UInt64 = 1) -> [Float] {
        var state = seed
        return (0..<Int(seconds * sampleRate)).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Float(state >> 40) / Float(1 << 24)
            return amplitude * (unit * 2 - 1)
        }
    }

    /// A kick drum on every beat at a known tempo: a short, low thump that dies away.
    static func kicks(beatsPerMinute: Double, seconds: Double, amplitude: Float = 0.8) -> [Float] {
        var sound = silence(seconds: seconds)
        let beatLength = 60 / beatsPerMinute
        var beat = 0
        while Double(beat) * beatLength < seconds {
            let start = Int(Double(beat) * beatLength * sampleRate)
            for offset in 0..<Int(0.3 * sampleRate) where start + offset < sound.count {
                let time = Double(offset) / sampleRate
                let thump = sin(2 * Double.pi * 80 * time) * exp(-time / 0.06)
                sound[start + offset] += amplitude * Float(thump)
            }
            beat += 1
        }
        return sound
    }

    /// A simple band: a kick on every beat, a snare on beats 2 and 4, a hi-hat and a
    /// softer bass note halfway between the beats.
    static func band(beatsPerMinute: Double, seconds: Double) -> [Float] {
        var sound = kicks(beatsPerMinute: beatsPerMinute, seconds: seconds, amplitude: 0.7)
        let hiss = noise(amplitude: 1, seconds: 0.2, seed: 9)
        let beatLength = 60 / beatsPerMinute
        func add(at start: Double, length: Double, _ wave: (Int, Double) -> Float) {
            let first = Int(start * sampleRate)
            for offset in 0..<Int(length * sampleRate) where first + offset < sound.count {
                sound[first + offset] += wave(offset, Double(offset) / sampleRate)
            }
        }
        var beat = 0
        while Double(beat) * beatLength < seconds {
            let start = Double(beat) * beatLength
            if beat % 2 == 1 {
                add(at: start, length: 0.18) { offset, time in 0.3 * hiss[offset] * Float(exp(-time / 0.05)) }
            }
            add(at: start + beatLength / 2, length: 0.05) { offset, time in
                0.12 * hiss[offset] * Float(exp(-time / 0.012))
            }
            add(at: start + beatLength / 2, length: beatLength * 0.45) { _, time in
                0.3 * Float(sin(2 * Double.pi * 65.4 * time) * min(1, time / 0.01) * exp(-time / 0.25))
            }
            beat += 1
        }
        return sound
    }
}

/// Plays test sound to an analyser the way the app does: the "audio thread" adds a small
/// chunk to the ring, then a "frame" asks for a reading.
final class TestListener {
    let ring = SampleRing(sampleRate: TestSound.sampleRate)
    private(set) lazy var analyser = SoundAnalyser(ring: ring)

    /// Feeds the sound in and returns the last reading.
    /// - Parameters:
    ///   - chunk: how many samples arrive between readings. 512 is what Core Audio hands
    ///     over at a time; 735 is one frame at 60 a second.
    ///   - eachReading: called after every chunk with the reading a frame would get.
    @discardableResult
    func hear(_ sound: [Float], chunk: Int = 512, eachReading: (SoundReading) -> Void = { _ in })
        -> SoundReading
    {
        var reading = analyser.update()
        var start = 0
        while start < sound.count {
            let count = min(chunk, sound.count - start)
            sound.withUnsafeBufferPointer { ring.write($0.baseAddress! + start, count: count) }
            start += count
            reading = analyser.update()
            eachReading(reading)
        }
        return reading
    }
}
