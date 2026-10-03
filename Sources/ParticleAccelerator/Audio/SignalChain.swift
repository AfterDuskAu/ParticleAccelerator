import Foundation

/// A part of the sound that can drive one of a visual's controls.
enum SoundSource: String, Codable, CaseIterable {
    case sub, kick, lowMids, mids, vocals, air
    /// The whole sound.
    case loudness
    /// A pulse on each beat.
    case beat

    var name: String {
        switch self {
        case .sub: return Band.sub.name
        case .kick: return Band.kick.name
        case .lowMids: return Band.lowMids.name
        case .mids: return Band.mids.name
        case .vocals: return Band.vocals.name
        case .air: return Band.air.name
        case .loudness: return "Loudness"
        case .beat: return "Beat"
        }
    }
}

extension Band {
    /// The band as something a control can be driven by.
    var source: SoundSource {
        switch self {
        case .sub: return .sub
        case .kick: return .kick
        case .lowMids: return .lowMids
        case .mids: return .mids
        case .vocals: return .vocals
        case .air: return .air
        }
    }
}

extension SoundReading {
    /// What one part of the sound is doing right now, from 0 to 1.
    func level(of source: SoundSource) -> Float {
        switch source {
        case .sub: return bands.sub
        case .kick: return bands.kick
        case .lowMids: return bands.lowMids
        case .mids: return bands.mids
        case .vocals: return bands.vocals
        case .air: return bands.air
        case .loudness: return loudness
        case .beat: return beat
        }
    }
}

/// Steps 2 to 4 of the signal chain: how a level from the sound is cleaned up before it
/// moves anything (docs/PLAN.md, "How the music drives a visual").
struct SignalShape: Codable, Equatable {
    /// Step 2, range: levels from `low` to `high` are stretched to 0–1. Anything below
    /// `low` is 0 and anything above `high` is 1.
    var low: Float = 0
    var high: Float = 1
    /// Step 3, curve: 1 is a straight line. Higher numbers bend it so only the strong
    /// hits show (2 turns a half-strength hit into a quarter).
    var steepness: Float = 1
    /// Step 4, fade: how long the value takes to climb most of the way to a higher
    /// level, and to fall most of the way back, in seconds. 0 is instant.
    var riseSeconds: Double = 0
    var fallSeconds: Double = 0.2

    /// Steps 2 and 3, which don't depend on what came before.
    func stretchAndBend(_ level: Float) -> Float {
        let span = high - low
        let stretched = span > 0 ? min(1, max(0, (level - low) / span)) : (level >= high ? 1 : 0)
        return steepness == 1 ? stretched : pow(stretched, max(0.01, steepness))
    }

    /// Step 4: moves `value` towards `target` for one frame that lasted `seconds`.
    /// It gives the same result at any frame rate.
    func fade(_ value: Float, towards target: Float, seconds: Double) -> Float {
        guard seconds > 0 else { return value }
        let duration = target > value ? riseSeconds : fallSeconds
        guard duration > 0 else { return target }
        return value + (target - value) * Float(1 - exp(-seconds / duration))
    }
}

/// The whole four-step chain for one control: which part of the sound, and how it's
/// shaped.
struct SignalChain: Codable, Equatable {
    /// Step 1, source.
    var source: SoundSource
    var shape = SignalShape()
}

/// A signal chain while it runs. It remembers the last value, which the fade needs.
struct LiveSignal {
    var chain: SignalChain
    private(set) var value: Float = 0

    init(_ chain: SignalChain) {
        self.chain = chain
    }

    /// Takes this frame's reading and returns the control's new value, from 0 to 1.
    /// - Parameter seconds: how long it's been since the last frame.
    mutating func update(_ reading: SoundReading, seconds: Double) -> Float {
        let target = chain.shape.stretchAndBend(reading.level(of: chain.source))
        value = chain.shape.fade(value, towards: target, seconds: seconds)
        return value
    }
}

/// The spectrum as a source: all 64 bars put through the same shape, each with a fade
/// of its own.
struct LiveSpectrum {
    var shape: SignalShape
    private(set) var bars = SIMD64<Float>(repeating: 0)

    init(_ shape: SignalShape = SignalShape()) {
        self.shape = shape
    }

    mutating func update(_ reading: SoundReading, seconds: Double) -> SIMD64<Float> {
        for index in 0..<SoundAnalyser.barCount {
            let target = shape.stretchAndBend(reading.bars[index])
            bars[index] = shape.fade(bars[index], towards: target, seconds: seconds)
        }
        return bars
    }
}
