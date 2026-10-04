import Foundation
import simd

/// The six bands' colours in one visual at any moment. Each visual has its own, so that
/// one can be locked while another is changed (the owner, 2026-10-04).
///
/// They're either fixed (the person's own, or the bands' own), or they change by
/// themselves: the colours drift slowly from one made-up set to the next and never
/// settle (the owner asked for this on 2026-10-04).
///
/// A made-up set is six hues spread round the colour wheel, a fixed step apart, so
/// neighbouring bands always stay far enough apart to tell at a glance. From one set
/// to the next the whole wheel turns and the step changes; no two bands ever cross.
///
/// The colours at a moment depend only on the clock, so the stage on its own thread
/// and the sound check on the main thread arrive at the same ones without sharing
/// anything.
struct BandPalette: Equatable {
    /// One colour for each band, sub first, for when they aren't changing: red, green
    /// and blue from 0 to 1, as a screen shows them.
    var own: [SIMD3<Float>]
    var changesByItself: Bool
    /// How long the drift from one made-up set to the next takes.
    var secondsForAChange: Double

    // The two controls that say whether and how fast a visual's colours change. Each
    // visual has its own, saved under its own number, as it has its own colours.
    static let changesKey = "coloursChange"
    static let secondsKey = "colourSeconds"

    /// Whether the visual's colours change by themselves: 0 for no, 1 for yes.
    static func changesControl(ofVisual visual: Int) -> VisualControl {
        controls(ofVisual: visual)[0]
    }

    static func secondsControl(ofVisual visual: Int) -> VisualControl {
        controls(ofVisual: visual)[1]
    }

    /// Both, for a visual: whether its colours change, then how fast.
    static func controls(ofVisual visual: Int) -> [VisualControl] {
        controlsOfBuiltVisuals[visual] ?? makeControls(ofVisual: visual)
    }

    /// Made once for each visual that's built: the stage asks for them every frame.
    private static let controlsOfBuiltVisuals: [Int: [VisualControl]] = Dictionary(
        uniqueKeysWithValues: StageRenderer.visuals.map { ($0.number, makeControls(ofVisual: $0.number)) })

    private static func makeControls(ofVisual visual: Int) -> [VisualControl] {
        let standard = StageRenderer.standard(ofVisual: visual)
        return [
            VisualControl(
                visual: visual, key: changesKey, name: "Change by themselves", group: "Colours", unit: .share,
                range: 0...1, base: 0, standard: standard[changesKey],
                help: "The colours drift slowly from one made-up set to the next, and never settle."),
            VisualControl(
                visual: visual, key: secondsKey, name: "A new set every", group: "Colours", unit: .seconds,
                range: 4...120, base: 20, standard: standard[secondsKey], spreadsEvenlyByRatio: true,
                help: "How long the colours take to drift from one set to the next."),
        ]
    }

    /// A visual's colours, as the person has them.
    init(_ values: ControlValues, visual: Int) {
        let controls = Self.controls(ofVisual: visual)
        own = Band.allCases.map { values.colour(of: $0, in: visual) }
        changesByItself = values.value(of: controls[0]) >= 0.5
        secondsForAChange = Double(values.value(of: controls[1]))
    }

    /// Each band's colour at a moment, sub first.
    /// - Parameter time: seconds on a steady clock. The stage and the sound check both
    ///   use the Mac's own (`CACurrentMediaTime`).
    func colours(at time: Double) -> [SIMD3<Float>] {
        guard changesByItself, secondsForAChange > 0, time.isFinite else { return own }
        let place = time / secondsForAChange
        let number = place.rounded(.down)
        let part = place - number
        // Slow away from each set and slow into the next.
        let ease = part * part * (3 - 2 * part)
        let from = Self.madeUpSet(Int64(number))
        let to = Self.madeUpSet(Int64(number) + 1)

        // The wheel turns the short way round.
        var turn = to.firstHue - from.firstHue
        if turn > 0.5 { turn -= 1 }
        if turn < -0.5 { turn += 1 }
        let firstHue = from.firstHue + turn * ease
        let step = from.step + (to.step - from.step) * ease
        let saturation = from.saturation + (to.saturation - from.saturation) * ease
        return Band.allCases.map { band in
            Self.colour(hue: firstHue + Double(band.rawValue) * step, saturation: saturation)
        }
    }

    // MARK: Made-up sets

    private struct MadeUpSet {
        /// The sub's hue, as a share of the way round the colour wheel.
        var firstHue: Double
        /// How far round the wheel each band is from the one before.
        var step: Double
        var saturation: Double
    }

    /// Different every time the app starts, so the colours aren't the same every day.
    private static let seed = UInt64.random(in: .min ... .max)

    /// The same set for the same number, every time it's asked for.
    private static func madeUpSet(_ number: Int64) -> MadeUpSet {
        func chance(_ which: UInt64) -> Double {
            // A well-mixed number from 0 to 1 ("splitmix64").
            var mixed = seed &+ UInt64(bitPattern: number) &* 0x9E37_79B9_7F4A_7C15 &+ which &* 0xD1B5_4A32_D192_ED03
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            mixed ^= mixed >> 31
            return Double(mixed >> 11) / Double(1 << 53)
        }
        return MadeUpSet(
            firstHue: chance(1),
            // Between 38 and 60 degrees apart: clearly different, and six of them never
            // go more than once round the wheel.
            step: 0.105 + 0.06 * chance(2),
            saturation: 0.72 + 0.23 * chance(3))
    }

    /// A full-brightness colour from its place on the colour wheel.
    static func colour(hue: Double, saturation: Double) -> SIMD3<Float> {
        let turn = hue - hue.rounded(.down)
        let sixth = turn * 6
        let rising = Float(sixth - sixth.rounded(.down))
        let low = Float(1 - saturation)
        let up = low + (1 - low) * rising
        let down = low + (1 - low) * (1 - rising)
        switch Int(sixth) % 6 {
        case 0: return SIMD3(1, up, low)
        case 1: return SIMD3(down, 1, low)
        case 2: return SIMD3(low, 1, up)
        case 3: return SIMD3(low, down, 1)
        case 4: return SIMD3(up, low, 1)
        default: return SIMD3(1, low, down)
        }
    }
}
