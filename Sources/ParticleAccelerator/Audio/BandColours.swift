import Foundation
import simd

/// Each band has one colour of its own, the same wherever the band is shown: the sound
/// check's bars and meters, and the sections of Visualizer 3. Warm for the bass through
/// to cool for the highs, and far enough apart to tell at a glance.
///
/// The owner asked for this on 2026-10-03: with every part of the spectrum in the same
/// colours, a busy passage was one mass and showed nothing.
extension Band {
    /// Red, green and blue from 0 to 1, as a screen shows them.
    var colour: SIMD3<Float> {
        switch self {
        case .sub: return SIMD3(1.00, 0.48, 0.10)  // orange
        case .kick: return SIMD3(1.00, 0.20, 0.58)  // pink
        case .lowMids: return SIMD3(0.66, 0.33, 1.00)  // violet
        case .mids: return SIMD3(0.22, 0.42, 1.00)  // blue
        case .vocals: return SIMD3(0.08, 0.80, 0.80)  // cyan
        case .air: return SIMD3(0.27, 0.84, 0.46)  // green
        }
    }

    /// The same colour as amounts of light, which is what the shaders add up. (A screen's
    /// numbers aren't amounts of light: half the number is about a fifth of the light.)
    var light: SIMD3<Float> {
        func asLight(_ shown: Float) -> Float {
            shown <= 0.04045 ? shown / 12.92 : pow((shown + 0.055) / 1.055, 2.4)
        }
        return SIMD3(asLight(colour.x), asLight(colour.y), asLight(colour.z))
    }

    /// Where a pitch falls among the spectrum's bars: 0 is the bottom of the first bar,
    /// and 64 is the top of the last.
    static func barPlace(ofHz hz: Float) -> Float {
        let wholeRange = log(SoundAnalyser.highestBarHz / SoundAnalyser.lowestBarHz)
        return Float(SoundAnalyser.barCount) * log(hz / SoundAnalyser.lowestBarHz) / wholeRange
    }

    /// The band a bar of the spectrum belongs to, by the pitch in the bar's middle.
    static func of(bar: Int) -> Band {
        let middle = Float(bar) + 0.5
        return allCases.last { barPlace(ofHz: $0.frequencies.lowerBound) <= middle } ?? .sub
    }
}
