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
    ///   - cameraMovement: the visual's own setting for it. A visual that leaves
    ///     trails wants less, or the trails smear.
    ///   - sparksGroup: the heading the visual keeps its sparks' controls under.
    init(visual: Int, cameraMovement: Float = 1, glow: Float = 0.7, sparksGroup: String = "Sparks") {
        func control(
            _ key: String, _ name: String, _ group: String, _ unit: VisualControl.Unit,
            _ range: ClosedRange<Float>, usual: Float, byRatio: Bool = false, _ help: String
        ) -> VisualControl {
            VisualControl(
                visual: visual, key: key, name: name, group: group, unit: unit, range: range, usual: usual,
                spreadsEvenlyByRatio: byRatio, help: help)
        }
        self.cameraMovement = control(
            "cameraMovement", "Camera movement", "Movement", .times, 0...4, usual: cameraMovement,
            "How far the camera drifts, rolls and breathes. At 0 it stands still.")
        beatPunch = control(
            "beatPunch", "Beat punch", "Movement", .times, 0...5, usual: 1,
            "How far the camera jumps towards the stage on each beat.")
        streaks = control(
            "streaks", "Streaks", sparksGroup, .times, 0...4, usual: 1,
            "How long a streak a fast spark leaves, the way a camera's shutter shows it. At 0 every spark is a dot.")
        self.glow = control(
            "glow", "Glow", "Picture", .times, 0...2.5, usual: glow,
            "How much everything bright glows.")
        brightness = control(
            "brightness", "Brightness", "Picture", .times, 0.3...3, usual: 1, byRatio: true,
            "How bright the whole picture is.")
        darkCorners = control(
            "darkCorners", "Dark corners", "Picture", .share, 0...1, usual: 0.5,
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
