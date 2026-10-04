import Foundation
import Metal
import simd

/// Visualizer 7, Corona (docs/VISUALS.md): Visualizer 4's tendrils, laid out so that
/// every strand belongs to its own bars of the spectrum. The strands still pour out of
/// a dark hole and curl like smoke, but how far each one reaches is how loud its own
/// bars are, so the ring of strands round the hole is the shape of the music.
///
/// With the music:
/// - The bands take their places round the hole, the same on the left as on the
///   right: sub at the bottom, then kick, low mids, mids and vocals, to air at the
///   top. Each is its band's colour.
/// - A strand reaches out as far as its own bars are loud, and brightens with them. It
///   does that at once: its sparks are already flowing along its whole length, and
///   only as much of it as the music calls for is lit.
/// - A fresh hit reaches further than a sound that holds, so beats show in a busy
///   song.
/// - The tip of each strand is brightest, so the tips trace the music's shape.
/// - The bass pushes every strand's sparks out faster, and the hole swells on each
///   kick. The highs make the specks sparkle.
///
/// The owner asked for this on 2026-10-04, as a copy of Visualizer 4 made "a lot more
/// responsive to their specific bars": with every strand flowing to the whole song,
/// and the curl mixing them, "it feels kind of chaotic".
final class Corona: Visual {
    static let number = 7

    /// The strands' brightness is set for this many sparks. With more, each is dimmer,
    /// so a higher quality gives finer strands and not a brighter picture.
    private static let sparksTheBrightnessIsSetFor: Float = 150_000
    /// How many sparks follow each other along one strand, when the person hasn't
    /// asked for more or fewer strands.
    private static let sparksInAStrand: Float = 130
    /// How far from the middle of the hole a strand's tip is at its loudest, on the
    /// stage, before the person's "Reach": nearly at the top of the picture, however
    /// big the hole is.
    private static let farthestTip: Float = 0.97
    /// A strand's stub at the rim, which shows even in silence.
    private static let stub: Float = 0.05

    private var mountains = ParticleWave.Mountains()
    private var bass = LiveSignal(
        SignalChain(source: .kick, shape: SignalShape(low: 0.15, high: 1, steepness: 1.2, riseSeconds: 0.03, fallSeconds: 0.3)))
    private var swell = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.3)))
    private var sparkle = LiveSignal(
        SignalChain(source: .air, shape: SignalShape(low: 0.2, high: 1, steepness: 1.2, riseSeconds: 0.02, fallSeconds: 0.18)))
    private var punch = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.28)))
    private let usualDrift = CameraDrift()
    /// How far the whole field has turned, added up frame by frame.
    private var turned: Float = 0
    /// The picture the last frame was drawn into. A new one (after the window changes
    /// size) has nothing in it to dim, and is cleared.
    private var lastPicture: MTLTexture?

    private let device: MTLDevice
    private let moveSparks: MTLComputePipelineState
    private let dimPicture: MTLRenderPipelineState
    private let drawSparks: MTLRenderPipelineState
    private var sparks: MTLBuffer
    private var sparkCount: Int

    init(device: MTLDevice, library: MTLLibrary, particleCount: Int) throws {
        self.device = device
        guard let step = library.makeFunction(name: "coronaMoveSparks") else {
            throw StageProblem(message: "A shader is missing: coronaMoveSparks.")
        }
        moveSparks = try device.makeComputePipelineState(function: step)
        dimPicture = try device.makeDimmingPipeline(
            library: library, vertex: "wholeScreen", fragment: "coronaDim")
        drawSparks = try device.makeLightPipeline(
            library: library, vertex: "coronaSpark", fragment: "sparkLight")
        sparkCount = particleCount
        sparks = try device.makePrivateBuffer(of: Self.startingSparks(count: particleCount), called: "sparks")
    }

    func setParticleCount(_ count: Int) throws {
        guard count != sparkCount else { return }
        sparks = try device.makePrivateBuffer(of: Self.startingSparks(count: count), called: "sparks")
        sparkCount = count
    }

    // MARK: Each frame

    func prepare(
        _ uniforms: inout StageUniforms, finishing: inout FinishUniforms, reading: SoundReading,
        values: ControlValues
    ) {
        let seconds = Double(uniforms.seconds)
        func value(_ control: VisualControl) -> Float { values.value(of: control) }

        // How far each strand reaches: the peaks over its own bars.
        Control.response.apply(to: &mountains, values: values)
        uniforms.bars = mountains.update(bars: reading.bars, seconds: seconds)

        let push = bass.update(reading, seconds: seconds) * value(Control.bassPush)
        let kick = swell.update(reading, seconds: seconds)
        uniforms.loudness = reading.loudness
        uniforms.beat = kick
        turned += value(Control.turning) * 0.05 * uniforms.seconds

        let drift = Control.common.drift(from: usualDrift, values: values)
        let camera = drift.camera(
            at: Double(uniforms.time), aspect: uniforms.aspect,
            punchNow: punch.update(reading, seconds: seconds) * reading.loudness)
        uniforms.viewProjection = camera.viewProjection
        uniforms.cameraPosition = SIMD4(camera.position, 0)
        uniforms.tanHalfFieldOfView = tan(camera.fieldOfView / 2)
        uniforms.focusDistance = drift.distance
        // Everything lies in one flat sheet, all of it in focus.
        uniforms.blurPerUnit = 0
        uniforms.fog = 0
        Control.common.finish(&finishing, values: values)

        // The hole swells on each kick.
        let hole = 0.17 * value(Control.holeSize) * (1 + 0.22 * kick * min(value(Control.bassPush), 2))
        // Where the hole is in the picture, for dimming: its middle from 0 to 1 each
        // way, and its radius as a share of the picture's height.
        let middle = camera.viewProjection * SIMD4<Float>(0, 0, 0, 1)
        let holeX = middle.x / middle.w * 0.5 + 0.5
        let holeY = 0.5 - middle.y / middle.w * 0.5
        let holeRadius = hole / (2 * max(middle.w, 0.05) * uniforms.tanHalfFieldOfView)
        // How much of the last frame is left after this one: all but a little, so a
        // trail takes "Trail" seconds to fade.
        let kept = Float(exp(-seconds / Double(max(value(Control.trail), 0.01))))

        var numbers = SIMD32<Float>(repeating: 0)
        func put(_ number: Float, in slot: Slot) { numbers[slot.rawValue] = number }
        put(hole, in: .hole)
        put(holeX, in: .holeX)
        put(holeY, in: .holeY)
        put(holeRadius, in: .holeRadius)
        put(kept, in: .kept)
        put(max(0.2, Self.farthestTip - 0.17 * value(Control.holeSize)) * value(Control.reach), in: .reach)
        put(Self.stub, in: .stub)
        put(value(Control.tips), in: .tips)
        put(0.30 * value(Control.speed), in: .speed)
        put(push, in: .push)
        put(0.20 * value(Control.curl), in: .curl)
        put(value(Control.curlSize), in: .curlSize)
        put(turned, in: .turned)
        put((Float(sparkCount) / Self.sparksInAStrand * value(Control.strands)).rounded(), in: .strands)
        put(value(Control.thickness), in: .thickness)
        // A longer trail keeps more of each spark's light on screen, so each spark
        // gives less: the picture's brightness stays the same.
        put(
            Self.sparksTheBrightnessIsSetFor / Float(max(sparkCount, 1)) * value(Control.brightness)
                * min(1, (1 - kept) * 9) * 0.11,
            in: .sparkLight)
        put(value(Control.specks), in: .specks)
        put((0.3 + 0.9 * sparkle.update(reading, seconds: seconds)) * value(Control.twinkle), in: .twinkle)
        uniforms.controls = numbers
    }

    func draw(_ frame: VisualFrame) {
        var uniforms = frame.uniforms
        let uniformsLength = MemoryLayout<StageUniforms>.stride
        var count = UInt32(sparkCount)

        // 1. The graphics card moves every spark along the current.
        if let compute = frame.commands.makeComputeCommandEncoder() {
            compute.setComputePipelineState(moveSparks)
            compute.setBuffer(sparks, offset: 0, index: 0)
            compute.setBytes(&uniforms, length: uniformsLength, index: 1)
            compute.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 2)
            let group = min(256, moveSparks.maxTotalThreadsPerThreadgroup)
            compute.dispatchThreadgroups(
                MTLSize(width: (sparkCount + group - 1) / group, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: group, height: 1, depth: 1))
            compute.endEncoding()
        }

        // 2. The last frame, dimmed a little, with the sparks drawn on top.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = frame.picture
        let isNewPicture = lastPicture !== frame.picture
        lastPicture = frame.picture
        pass.colorAttachments[0].loadAction = isNewPicture ? .clear : .load
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let render = frame.commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        render.setVertexBytes(&uniforms, length: uniformsLength, index: 1)
        render.setFragmentBytes(&uniforms, length: uniformsLength, index: 1)

        render.setRenderPipelineState(dimPicture)
        render.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        render.setRenderPipelineState(drawSparks)
        render.setVertexBuffer(sparks, offset: 0, index: 0)
        render.drawPrimitives(type: .point, vertexStart: 0, vertexCount: sparkCount)
        render.endEncoding()
    }

    // MARK: The controls

    enum Control {
        private static func control(
            _ key: String, _ name: String, _ group: String, _ unit: VisualControl.Unit,
            _ range: ClosedRange<Float>, base: Float, byRatio: Bool = false, _ help: String
        ) -> VisualControl {
            VisualControl(
                visual: Corona.number, key: key, name: name, group: group, unit: unit, range: range,
                base: base, standard: Corona.standard[key], spreadsEvenlyByRatio: byRatio, help: help)
        }

        /// The camera moves less than in the other visuals: the trails are left where
        /// the picture was, so a moving camera smears them.
        static let common = CommonControls(
            visual: Corona.number, cameraMovement: 0.3, glow: 0.3, sparksGroup: "Strands",
            standard: Corona.standard)
        static let response = ResponseControls(visual: Corona.number, standard: Corona.standard)

        static let reach = control(
            "reach", "Reach", "Reach", .times, 0.3...2, base: 1, byRatio: true,
            "How far a strand reaches when its part of the music is at its loudest.")
        static let tips = control(
            "tips", "Tips", "Reach", .times, 0...4, base: 1,
            "How bright the tip of each strand is. Together the tips trace the music's shape round the hole.")

        static let speed = control(
            "speed", "Speed", "Flow", .times, 0.2...4, base: 1, byRatio: true,
            "How fast the sparks run out along the strands. A strand's sparks run faster as its part of the music gets louder.")
        static let bassPush = control(
            "bassPush", "Bass push", "Flow", .times, 0...4, base: 1,
            "How much the bass pushes every strand's sparks out faster, and swells the hole on each kick.")
        static let curl = control(
            "curl", "Curl", "Flow", .times, 0...4, base: 0.6,
            "How much the strands wander and curl, like smoke in a slow current. The more they curl, the more the bands run into each other.")
        static let curlSize = control(
            "curlSize", "Curl size", "Flow", .times, 0.3...3, base: 1, byRatio: true,
            "How big the swirls are. Small makes tight ripples; large makes long slow bends.")
        static let turning = control(
            "turning", "Turning", "Flow", .times, 0...6, base: 0,
            "How fast the whole ring turns round the hole. At 0 the bass stays at the bottom and the highs at the top.")
        static let holeSize = control(
            "holeSize", "Hole size", "Flow", .times, 0.3...3, base: 1, byRatio: true,
            "How big the dark hole in the middle is.")

        static let strands = control(
            "strands", "Strands", "Strands", .times, 0.25...4, base: 1, byRatio: true,
            "How many strands there are. More strands are finer, with fewer sparks along each.")
        static let trail = control(
            "trail", "Trail", "Strands", .seconds, 0.03...3, base: 0.12, byRatio: true,
            "How long a spark's trail takes to fade. Longer joins the sparks into smooth lines but lets go of a beat more slowly; shorter shows them as beads.")
        static let thickness = control(
            "thickness", "Thickness", "Strands", .times, 0.4...3, base: 1, byRatio: true,
            "How thick each strand is.")
        static let brightness = control(
            "strandBrightness", "Brightness", "Strands", .times, 0.2...4, base: 1, byRatio: true,
            "How bright the strands are.")
        static let specks = control(
            "specks", "Specks", "Strands", .share, 0...0.2, base: 0.03,
            "The share of sparks that are bright specks running along the strands.")
        static let twinkle = control(
            "twinkle", "Twinkle", "Strands", .times, 0...2, base: 1,
            "How much the specks flicker. The highs in the music add to it.")
    }

    static let controls: [VisualControl] =
        [Control.reach, Control.tips] + Control.response.all + [
            Control.speed, Control.bassPush, Control.curl, Control.curlSize, Control.turning, Control.holeSize,
            Control.strands, Control.trail, Control.thickness, Control.brightness, Control.specks, Control.twinkle,
            Control.common.cameraMovement, Control.common.beatPunch,
            Control.common.glow, Control.common.brightness, Control.common.darkCorners,
        ]

    /// The owner's standard (2026-10-04). It began as their Visualizer 4's
    /// (`Tendrils.standard`), and that afternoon they tuned it for itself: four times
    /// as many strands, finer and brighter, reaching far with bright tips; small,
    /// tight curls; a small hole and a ring that turns; a strong push from the bass;
    /// bars that move with their neighbours and let go quickly; a camera that moves a
    /// lot; and colours that stay as they are. Anything not listed is at its base.
    static let standard: [String: Float] = [
        "reach": 1.71, "tips": 3.71,
        "quietPitches": 4.42, "heldSound": 0.86, "responseWidth": 8, "fall": 0.052,
        "speed": 1.03, "bassPush": 3.30, "curl": 1.84, "curlSize": 0.31, "turning": 1.06, "holeSize": 0.81,
        "strands": 4, "trail": 0.14, "thickness": 0.76, "strandBrightness": 1.68, "twinkle": 0.98,
        "cameraMovement": 4, "beatPunch": 1.60,
        BandPalette.secondsKey: 4.68,
    ]

    // MARK: The sparks

    /// One spark, as the graphics card keeps it: 64 bytes.
    struct Spark {
        /// x, y, z, and its age from 0 (leaving the rim) to 1 (gone).
        var position: SIMD4<Float>
        /// How fast it's going each way, and how many seconds it lasts.
        var velocity: SIMD4<Float>
        /// x: its strand's place across the six bands' sections, from 0 (the bottom
        /// of the sub) to 1 (the top of the air). y: how many times it's set out.
        /// z: how bright its strand is. w: its own unchanging number from 0 to 1.
        var nature: SIMD4<Float>
        /// Its light (its colour times its brightness) and its size on the stage.
        var look: SIMD4<Float>
    }

    /// The sparks before any has set out. The first time each is moved it takes a
    /// place somewhere along its strand. The same every time, so tests see the same
    /// picture.
    static func startingSparks(count: Int) -> [Spark] {
        (0..<count).map { index in
            let own = Double(index) + 0.5
            let number = Float((own * 0.618_033_988_749_895).truncatingRemainder(dividingBy: 1))
            let age = Float((own * 0.754_877_666_246_693).truncatingRemainder(dividingBy: 1))
            // Nowhere yet: each sets out from the rim the first time it's moved.
            return Spark(
                position: SIMD4(0, 0, 0, age), velocity: SIMD4(0, 0, 0, 4), nature: SIMD4(0, -1, 0, number),
                look: .zero)
        }
    }

    // MARK: The shaders

    /// Where each number sits among the uniforms' `controls`. The shaders are given the
    /// same names ("corona_reach"). The peaks over the spectrum's bars are in the
    /// uniforms' `bars`.
    private enum Slot: Int, CaseIterable {
        /// The hole's radius on the stage, and where it is in the picture.
        case hole, holeX, holeY, holeRadius
        /// How much of the last frame is kept.
        case kept
        /// How far a strand reaches at its loudest, and its stub in silence.
        case reach, stub, tips
        case speed, push, curl, curlSize, turned, strands, thickness, sparkLight, specks, twinkle
    }

    private static let slotsSource = Slot.allCases
        .map { "constant int corona_\($0) = \($0.rawValue);" }
        .joined(separator: "\n")

    static let shaderSource = """
        struct CoronaSpark {
            float4 position;   // x, y, z, and age from 0 (leaving the rim) to 1 (gone)
            float4 velocity;   // how fast it's going each way, and how many seconds it lasts
            float4 nature;     // its place across the bands, times set out, its strand's strength, its own number
            float4 look;       // its light (colour times brightness), and its size on the stage
        };

        \(slotsSource)

        // The slow current the strands curl in, at a place and a moment: a few broad
        // waves of different sizes crossing each other. It never squeezes the strands
        // together or pulls them apart, only bends them, the way smoke moves.
        static float2 coronaCurrent(float2 place, float time, float size) {
            const float2 wave0 = float2(1.7, 2.3);
            const float2 wave1 = float2(-3.1, 1.9);
            const float2 wave2 = float2(2.9, -4.3);
            const float2 wave3 = float2(-5.9, -3.7);
            const float2 wave4 = float2(9.1, 6.3);
            float2 slope = float2(0.0);
            slope += normalize(wave0) * cos(dot(wave0, place) / size + time * 0.11 + 0.3);
            slope += normalize(wave1) * cos(dot(wave1, place) / size - time * 0.09 + 1.9);
            slope += normalize(wave2) * cos(dot(wave2, place) / size + time * 0.14 + 4.1) * 0.8;
            slope += normalize(wave3) * cos(dot(wave3, place) / size - time * 0.17 + 2.6) * 0.6;
            slope += normalize(wave4) * cos(dot(wave4, place) / size + time * 0.21 + 5.2) * 0.35;
            return float2(slope.y, -slope.x) * 0.5;
        }

        // Moves every spark on by one frame.
        kernel void coronaMoveSparks(device CoronaSpark *sparks [[buffer(0)]],
                                     constant StageUniforms &stage [[buffer(1)]],
                                     constant uint &count [[buffer(2)]],
                                     uint index [[thread_position_in_grid]]) {
            if (index >= count) return;
            CoronaSpark spark = sparks[index];
            float own = spark.nature.w;
            float journeys = spark.nature.y;
            float hole = stage.controls[corona_hole];
            float fullReach = stage.controls[corona_reach];
            float life = max(spark.velocity.w, 0.5);
            float age = spark.position.w + stage.seconds / life;
            float far = length(spark.position.xy);
            // Where the longest strand ends. A spark runs the whole way there, lit or
            // not, so that every strand has sparks along all of it, ready to be lit.
            float end = hole + fullReach * 1.08 + 0.05;

            if (age >= 1.0 || journeys < 0.0 || far > end) {
                // At the end of its strand (or it has wandered for too long): set out
                // again from its strand's place on the rim.
                bool isFirst = journeys < 0.0;
                age = 0.0;
                journeys = max(journeys, 0.0) + 1.0;
                float strands = max(stage.controls[corona_strands], 6.0);
                float strand = floor(own * strands);
                // Strands aren't evenly spaced: they bunch a little, as hair does.
                float round = (strand + 0.5 * chance(strand * 12.9898)) / strands;
                // Round from the bottom of the hole: the sub is there, and the bands
                // climb both sides to the air at the top.
                float angle = round * 6.2832 + stage.controls[corona_turned];
                float2 heading = float2(sin(angle), -cos(angle));
                far = hole * (1.01 + 0.03 * sparkChance(index, uint(journeys) * 4u));
                // The very first time, it starts somewhere along its strand, so that
                // the strands are full from the first frame.
                if (isFirst) far = mix(far, end, sparkChance(index, 1u));
                spark.position.xy = heading * far;
                spark.position.z = 0.0;
                // Long enough to run the whole strand at any but the slowest speed.
                spark.velocity.w = mix(16.0, 26.0, chance(strand * 78.233));
                spark.nature.x = 1.0 - fabs(2.0 * round - 1.0);
                // Some strands are bright and most are faint, so that the brighter
                // ones stand out as separate lines with darker gaps between.
                float strength = chance(strand * 39.346);
                spark.nature.z = mix(0.3, 2.2, strength * strength);
            }

            // How loud its own bars are now: that's how far its strand reaches.
            float level = spectrumAt(stage, sectionSpectrumAt(spark.nature.x));
            float reach = hole + stage.controls[corona_stub] + fullReach * level;

            // Outward, faster as its own bars get louder and when the bass pushes; and
            // bent by the current, more the further out it is.
            float2 outward = spark.position.xy / max(far, 0.001);
            float speed = stage.controls[corona_speed]
                * (0.5 + 0.9 * level + 0.5 * stage.controls[corona_push]);
            float2 current = coronaCurrent(spark.position.xy, stage.time, stage.controls[corona_curlSize]);
            float bent = smoothstep(hole, hole + 0.6, far);
            float2 velocity = outward * speed + current * stage.controls[corona_curl] * bent * (0.6 + far);
            spark.velocity.xy = velocity;
            spark.position.xy += velocity * stage.seconds;
            far = length(spark.position.xy);

            // How it looks: its band's colour, lit only as far out as its strand
            // reaches now, and brightest at the tip.
            int band = sectionBandAt(spark.nature.x);
            float3 colour = bandLightOf(stage, band);
            float fade = smoothstep(0.0, 0.004, age) * (1.0 - smoothstep(0.9, 1.0, age));
            // (Where they leave the rim the strands are packed tightest. Dimming them
            // there keeps the rim from glaring, which would spill light into the hole.)
            fade *= mix(0.3, 1.0, smoothstep(hole, hole + 0.14, far));
            float lit = 1.0 - smoothstep(reach - 0.05, reach, far);
            float tip = smoothstep(reach - 0.14, reach - 0.03, far) * lit;
            bool isSpeck = chance(own * 47.9 + journeys) < stage.controls[corona_specks];
            float bright = stage.controls[corona_sparkLight] * fade * lit * (0.35 + 1.2 * level)
                * (1.0 + 1.6 * stage.controls[corona_tips] * tip) * spark.nature.z;
            float size = 0.0015 * stage.controls[corona_thickness];
            if (isSpeck) {
                // A speck: paler, bigger, far brighter, and twinkling.
                colour = mix(colour, float3(1.0), 0.6);
                float twinkle = 1.0 + stage.controls[corona_twinkle]
                    * sin(stage.time * (3.0 + 9.0 * chance(own * 17.3)) + own * 200.0);
                bright *= 26.0 * max(twinkle, 0.1);
                size *= 2.2;
            }
            spark.look = float4(colour * bright, size);
            spark.position.w = age;
            spark.nature.y = journeys;
            sparks[index] = spark;
        }

        vertex SparkOut coronaSpark(const device CoronaSpark *sparks [[buffer(0)]],
                                    constant StageUniforms &stage [[buffer(1)]],
                                    uint id [[vertex_id]]) {
            CoronaSpark spark = sparks[id];
            // One that hasn't set out, or is past the lit part of its strand, isn't
            // drawn at all.
            if (spark.nature.y < 0.0 || dot(spark.look.rgb, float3(1.0)) <= 0.0) return noSpark();
            // Drawn from where it was last frame to where it is now, so that one
            // frame's mark joins the next and the trail has no gaps.
            float3 before = spark.position.xyz - float3(spark.velocity.xy, 0.0) * stage.seconds;
            return makeSpark(stage, spark.position.xyz, before, spark.look.w, spark.look.rgb);
        }

        // Dims the last frame: a little everywhere, and to nothing inside the hole.
        fragment half4 coronaDim(ScreenOut in [[stage_in]], constant StageUniforms &stage [[buffer(1)]]) {
            float2 fromHole = (in.uv - float2(stage.controls[corona_holeX], stage.controls[corona_holeY]))
                * float2(stage.aspect, 1.0);
            float radius = stage.controls[corona_holeRadius];
            float outside = smoothstep(radius * 0.94, radius * 1.0, length(fromHole));
            return half4(half3(stage.controls[corona_kept] * outside), 1.0h);
        }
        """
}
