import Foundation
import Metal
import simd

/// The controls every visual has: how the camera moves, how a camera would see its
/// sparks, and how the picture is finished. Each visual gets a set of its own, saved
/// under its own number, so changing one visual's glow leaves the others' alone.
struct CommonControls {
    let cameraMovement: VisualControl
    let beatPunch: VisualControl
    let streaks: VisualControl
    let glow: VisualControl
    let brightness: VisualControl
    let darkCorners: VisualControl

    /// - Parameters:
    ///   - cameraMovement: the visual's own base setting for it. A visual that leaves
    ///     trails wants less, or the trails smear.
    ///   - sparksGroup: the heading the visual keeps its sparks' controls under.
    ///   - standard: the visual's standard (`Visual.standard`).
    init(
        visual: Int, cameraMovement: Float = 1, glow: Float = 0.7, sparksGroup: String = "Sparks",
        standard: [String: Float] = [:]
    ) {
        func control(
            _ key: String, _ name: String, _ group: String, _ unit: VisualControl.Unit,
            _ range: ClosedRange<Float>, base: Float, byRatio: Bool = false, _ help: String
        ) -> VisualControl {
            VisualControl(
                visual: visual, key: key, name: name, group: group, unit: unit, range: range, base: base,
                standard: standard[key], spreadsEvenlyByRatio: byRatio, help: help)
        }
        self.cameraMovement = control(
            "cameraMovement", "Camera movement", "Movement", .times, 0...4, base: cameraMovement,
            "How far the camera drifts, rolls and breathes. At 0 it stands still.")
        beatPunch = control(
            "beatPunch", "Beat punch", "Movement", .times, 0...5, base: 1,
            "How far the camera jumps towards the stage on each beat.")
        streaks = control(
            "streaks", "Streaks", sparksGroup, .times, 0...4, base: 1,
            "How long a streak a fast spark leaves, the way a camera's shutter shows it. At 0 every spark is a dot.")
        self.glow = control(
            "glow", "Glow", "Picture", .times, 0...2.5, base: glow,
            "How much everything bright glows.")
        brightness = control(
            "brightness", "Brightness", "Picture", .times, 0.3...3, base: 1, byRatio: true,
            "How bright the whole picture is.")
        darkCorners = control(
            "darkCorners", "Dark corners", "Picture", .share, 0...1, base: 0.5,
            "How much the picture darkens towards its corners.")
    }

    /// The camera's movements, scaled by the person's settings.
    func drift(from usual: CameraDrift, values: ControlValues) -> CameraDrift {
        var drift = usual
        let movement = values.value(of: cameraMovement)
        drift.sideways *= movement
        drift.upAndDown *= movement
        drift.roll *= movement
        drift.breath *= movement
        drift.punch *= values.value(of: beatPunch)
        return drift
    }

    func finish(_ finishing: inout FinishUniforms, values: ControlValues) {
        finishing.glow = values.value(of: glow)
        finishing.exposure = values.value(of: brightness)
        finishing.vignette = values.value(of: darkCorners)
    }

    /// How long a moment a spark's streak covers, in seconds: the hundred-and-twentieth
    /// of a second a film camera's shutter usually stays open for, times the person's
    /// setting.
    func shutterSeconds(values: ControlValues) -> Float {
        values.value(of: streaks) / 120
    }
}

/// Remembers when the last four kicks landed, for visuals that start something on
/// each one (a ripple, a burst).
struct KickClock {
    private var times = SIMD4<Float>(repeating: -1_000)
    private var next = 0
    private var beatsSeen = 0
    /// How many kicks had landed when each of the four was noted. A shader can make
    /// each burst different with it.
    private(set) var numbers = SIMD4<Float>(repeating: 0)

    /// How many seconds ago each of the last four kicks landed.
    /// - Parameter time: seconds since the stage started.
    mutating func ages(reading: SoundReading, time: Float) -> SIMD4<Float> {
        if reading.beatsHeard != beatsSeen {
            if reading.beatsHeard > beatsSeen {
                times[next] = time
                numbers[next] = Float(reading.beatsHeard % 4_096)
                next = (next + 1) % 4
            }
            beatsSeen = reading.beatsHeard
        }
        return SIMD4(repeating: time) - times
    }
}

extension MTLDevice {
    /// Puts these in memory only the graphics card uses, which is where it works on
    /// them fastest.
    /// - Parameter what: what they are, for the message if there's no room: "sparks".
    func makePrivateBuffer<Item>(of items: [Item], called what: String) throws -> MTLBuffer {
        let length = items.count * MemoryLayout<Item>.stride
        guard length > 0,
            let filled = items.withUnsafeBytes({ bytes in
                bytes.baseAddress.flatMap { makeBuffer(bytes: $0, length: length, options: .storageModeShared) }
            }),
            let buffer = makeBuffer(length: length, options: .storageModePrivate),
            let queue = makeCommandQueue(), let commands = queue.makeCommandBuffer(),
            let copy = commands.makeBlitCommandEncoder()
        else {
            throw StageProblem(
                message: "The graphics card couldn't make room for \(items.count.formatted()) \(what). Try a lower quality.")
        }
        copy.copy(from: filled, sourceOffset: 0, to: buffer, destinationOffset: 0, size: length)
        copy.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return buffer
    }
}

/// The spectrum laid out as six equal sections, one for each band, in the sound
/// check's order: sub, kick, low mids, mids, vocals, air. Each band's own bars are
/// spread across its section.
///
/// Visualizers 7 and 8 are laid out this way, so that every part of the picture
/// belongs to particular bars and moves only with them (the owner, 2026-10-04: "a lot
/// more responsive to their specific bars").
enum BandSections {
    /// Where each band starts among the 64 bars, with the end of the last: seven
    /// numbers from 0 to 64. (The sub starts below the first bar, so its section
    /// starts at the first bar.)
    static let barEdges: [Float] =
        Band.allCases.map { max(0, Band.barPlace(ofHz: $0.frequencies.lowerBound)) }
        + [Float(SoundAnalyser.barCount)]

    /// The bars a part of a band's section covers: those whose middles are inside it,
    /// so that no bar counts for two parts. A part narrower than a bar has the one bar
    /// its own middle is in.
    /// - Parameters:
    ///   - part: which part, counting from 0.
    ///   - parts: how many equal parts the band's section is cut into.
    static func bars(ofPart part: Int, of parts: Int, in band: Band) -> ClosedRange<Int> {
        let from = barEdges[band.rawValue]
        let width = (barEdges[band.rawValue + 1] - from) / Float(max(parts, 1))
        let lower = from + width * Float(part)
        let upper = lower + width
        let top = SoundAnalyser.barCount - 1
        let first = max(0, Int((lower - 0.5).rounded(.up)))
        let last = min(top, Int((upper - 0.5).rounded(.up)) - 1)
        guard first <= last else {
            let bar = min(top, max(0, Int(((lower + upper) / 2).rounded(.down))))
            return bar...bar
        }
        return first...last
    }

    /// For the shaders: a place across the six sections, from 0 to 1, as its band and
    /// as a place along the spectrum (for `spectrumAt`).
    static let metalSource: String = """
        constant float sectionBarEdges[7] = { \(barEdges.map { "\($0)" }.joined(separator: ", ")) };

        static int sectionBandAt(float place) {
            return clamp(int(place * 6.0), 0, 5);
        }

        static float sectionSpectrumAt(float place) {
            float six = clamp(place, 0.0, 0.99999) * 6.0;
            int band = int(six);
            float bar = mix(sectionBarEdges[band], sectionBarEdges[band + 1], six - float(band));
            return (bar - 0.5) / \(SoundAnalyser.barCount - 1).0;
        }
        """
}

/// The controls for how closely a visual follows its bars, for the visuals laid out in
/// band sections. They set up the same peaks Visualizer 3 stands its sparks on
/// (`ParticleWave.Mountains`): each part of the spectrum is measured against its own
/// recent loudest moment, and a fresh hit stands taller than a sound that holds.
struct ResponseControls {
    let quietPitches: VisualControl
    let heldSound: VisualControl
    let width: VisualControl
    let fall: VisualControl

    /// - Parameter standard: the visual's standard (`Visual.standard`).
    init(visual: Int, standard: [String: Float] = [:]) {
        func control(
            _ key: String, _ name: String, _ unit: VisualControl.Unit, _ range: ClosedRange<Float>,
            base: Float, byRatio: Bool = false, _ help: String
        ) -> VisualControl {
            VisualControl(
                visual: visual, key: key, name: name, group: "Response", unit: unit, range: range, base: base,
                standard: standard[key], spreadsEvenlyByRatio: byRatio, help: help)
        }
        quietPitches = control(
            "quietPitches", "Quieter pitches", .decibels, 2...14, base: 6,
            "A pitch this much quieter than the loudest nearby shows half as strongly. Higher shows more of the quieter pitches; lower leaves only the strongest.")
        heldSound = control(
            "heldSound", "Held sound", .share, 0.1...1, base: 0.35,
            "How strongly a sound that holds steady shows. Lower makes each fresh hit stand out more.")
        width = control(
            "responseWidth", "Width", .bars, 1...8, base: 1.5,
            "How far a loud pitch spreads to the bars beside it. Narrow keeps neighbours apart; wide moves them together.")
        fall = control(
            "fall", "Fall", .seconds, 0.03...1.5, base: 0.12, byRatio: true,
            "How long the picture takes to let go when a sound stops. Lower keeps one beat clear of the next; higher lets it hang.")
    }

    var all: [VisualControl] { [quietPitches, heldSound, width, fall] }

    /// Sets the peaks up as the person has them.
    func apply(to mountains: inout ParticleWave.Mountains, values: ControlValues) {
        mountains.decibelsToHalve = values.value(of: quietPitches)
        mountains.heldShare = values.value(of: heldSound)
        mountains.footprint = values.value(of: width)
        mountains.fallSeconds = Double(values.value(of: fall))
    }
}
