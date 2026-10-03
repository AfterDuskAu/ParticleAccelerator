import Foundation
import Metal
import simd

/// Visualizer 4, Tendrils (docs/VISUALS.md): a dark round hole in the middle, with
/// thousands of fine strands of light pouring outward from its rim, curling like smoke
/// in a slow current, and specks of light running along them.
///
/// With the music:
/// - Each strand belongs to a band and is its colour. The bands take turns round the
///   hole, three sprays each, and a spray surges outward and brightens with its band.
/// - The bass pushes every strand out faster, and the hole swells on each kick.
/// - The highs make the specks sparkle.
///
/// A strand isn't one thing: it's a file of sparks following each other out from the
/// same place on the rim. Each frame the last picture is dimmed a little and the
/// sparks are drawn on top, so each spark leaves a short trail and the file joins up
/// into a line.
///
/// This is its base design (2026-10-04): the owner tunes it from here with its
/// controls.
final class Tendrils: Visual {
    static let number = 4

    /// The strands' brightness is set for this many sparks. With more, each is dimmer,
    /// so a higher quality gives finer strands and not a brighter picture.
    private static let sparksTheBrightnessIsSetFor: Float = 150_000
    /// How many sparks follow each other along one strand, when the person hasn't
    /// asked for more or fewer strands.
    private static let sparksInAStrand: Float = 130

    private var bass = LiveSignal(
        SignalChain(source: .kick, shape: SignalShape(low: 0.15, high: 1, steepness: 1.2, riseSeconds: 0.03, fallSeconds: 0.3)))
    private var swell = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.3)))
    private var sparkle = LiveSignal(
        SignalChain(source: .air, shape: SignalShape(low: 0.2, high: 1, steepness: 1.2, riseSeconds: 0.02, fallSeconds: 0.18)))
    private var punch = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.28)))
    private var bandLevels = Band.allCases.map { band in
        LiveSignal(SignalChain(source: band.source, shape: SignalShape(riseSeconds: 0.03, fallSeconds: 0.3)))
    }
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
        guard let step = library.makeFunction(name: "tendrilMoveSparks") else {
            throw StageProblem(message: "A shader is missing: tendrilMoveSparks.")
        }
        moveSparks = try device.makeComputePipelineState(function: step)
        dimPicture = try device.makeDimmingPipeline(
            library: library, vertex: "wholeScreen", fragment: "tendrilDim")
        drawSparks = try device.makeLightPipeline(
            library: library, vertex: "tendrilSpark", fragment: "sparkLight")
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

        let push = bass.update(reading, seconds: seconds) * value(Control.bassPush)
        let kick = swell.update(reading, seconds: seconds)
        uniforms.loudness = reading.loudness
        uniforms.beat = kick
        for band in Band.allCases {
            uniforms.bands[band.rawValue] = bandLevels[band.rawValue].update(reading, seconds: seconds)
        }
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
                * min(1, (1 - kept) * 9) * 0.16,
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
            _ range: ClosedRange<Float>, usual: Float, byRatio: Bool = false, _ help: String
        ) -> VisualControl {
            VisualControl(
                visual: Tendrils.number, key: key, name: name, group: group, unit: unit, range: range,
                usual: usual, spreadsEvenlyByRatio: byRatio, help: help)
        }

        /// The camera moves less than in the other visuals: the trails are left where
        /// the picture was, so a moving camera smears them.
        static let common = CommonControls(
            visual: Tendrils.number, cameraMovement: 0.3, glow: 0.3, sparksGroup: "Strands")

        static let speed = control(
            "speed", "Speed", "Flow", .times, 0.2...4, usual: 1, byRatio: true,
            "How fast the strands pour outward. Each band's strands go faster as it gets louder.")
        static let bassPush = control(
            "bassPush", "Bass push", "Flow", .times, 0...4, usual: 1,
            "How much the bass pushes every strand out faster, and swells the hole on each kick.")
        static let curl = control(
            "curl", "Curl", "Flow", .times, 0...4, usual: 1,
            "How much the strands wander and curl, like smoke in a slow current.")
        static let curlSize = control(
            "curlSize", "Curl size", "Flow", .times, 0.3...3, usual: 1, byRatio: true,
            "How big the swirls are. Small makes tight ripples; large makes long slow bends.")
        static let turning = control(
            "turning", "Turning", "Flow", .times, 0...6, usual: 1,
            "How fast the whole field turns round the hole.")
        static let holeSize = control(
            "holeSize", "Hole size", "Flow", .times, 0.3...3, usual: 1, byRatio: true,
            "How big the dark hole in the middle is.")

        static let strands = control(
            "strands", "Strands", "Strands", .times, 0.25...4, usual: 1, byRatio: true,
            "How many strands there are. More strands are finer, with fewer sparks along each.")
        static let trail = control(
            "trail", "Trail", "Strands", .seconds, 0.05...3, usual: 0.35, byRatio: true,
            "How long a spark's trail takes to fade. Longer joins the sparks into smooth lines; shorter shows them as beads.")
        static let thickness = control(
            "thickness", "Thickness", "Strands", .times, 0.4...3, usual: 1, byRatio: true,
            "How thick each strand is.")
        static let brightness = control(
            "strandBrightness", "Brightness", "Strands", .times, 0.2...4, usual: 1, byRatio: true,
            "How bright the strands are.")
        static let specks = control(
            "specks", "Specks", "Strands", .share, 0...0.2, usual: 0.03,
            "The share of sparks that are bright specks running along the strands.")
        static let twinkle = control(
            "twinkle", "Twinkle", "Strands", .times, 0...2, usual: 1,
            "How much the specks flicker. The highs in the music add to it.")
    }

    static let controls: [VisualControl] = [
        Control.speed, Control.bassPush, Control.curl, Control.curlSize, Control.turning, Control.holeSize,
        Control.strands, Control.trail, Control.thickness, Control.brightness, Control.specks, Control.twinkle,
        Control.common.cameraMovement, Control.common.beatPunch,
        Control.common.glow, Control.common.brightness, Control.common.darkCorners,
    ]

    // MARK: The sparks

    /// One spark, as the graphics card keeps it: 64 bytes.
    struct Spark {
        /// x, y, z, and its age from 0 (leaving the rim) to 1 (gone).
        var position: SIMD4<Float>
        /// How fast it's going each way, and how many seconds it lasts.
        var velocity: SIMD4<Float>
        /// x: its band. y: how many times it's set out. z: how bright its strand is.
        /// w: its own unchanging number from 0 to 1.
        var nature: SIMD4<Float>
        /// Its light (its colour times its brightness) and its size on the stage.
        var look: SIMD4<Float>
    }

    /// The sparks before any has set out, at different ages so they don't all leave
    /// the rim together. The same every time, so tests see the same picture.
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
    /// same names ("tendril_speed").
    private enum Slot: Int, CaseIterable {
        /// The hole's radius on the stage, and where it is in the picture.
        case hole, holeX, holeY, holeRadius
        /// How much of the last frame is kept.
        case kept
        case speed, push, curl, curlSize, turned, strands, thickness, sparkLight, specks, twinkle
    }

    private static let slotsSource = Slot.allCases
        .map { "constant int tendril_\($0) = \($0.rawValue);" }
        .joined(separator: "\n")

    static let shaderSource = """
        struct TendrilSpark {
            float4 position;   // x, y, z, and age from 0 (leaving the rim) to 1 (gone)
            float4 velocity;   // how fast it's going each way, and how many seconds it lasts
            float4 nature;     // its band, times set out, how strong its strand is, its own number
            float4 look;       // its light (colour times brightness), and its size on the stage
        };

        \(slotsSource)

        // The slow current the strands curl in, at a place and a moment: a few broad
        // waves of different sizes crossing each other. It never squeezes the strands
        // together or pulls them apart, only bends them, the way smoke moves.
        static float2 tendrilCurrent(float2 place, float time, float size) {
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
        kernel void tendrilMoveSparks(device TendrilSpark *sparks [[buffer(0)]],
                                      constant StageUniforms &stage [[buffer(1)]],
                                      constant uint &count [[buffer(2)]],
                                      uint index [[thread_position_in_grid]]) {
            if (index >= count) return;
            TendrilSpark spark = sparks[index];
            float own = spark.nature.w;
            float journeys = spark.nature.y;
            float hole = stage.controls[tendril_hole];
            float life = max(spark.velocity.w, 0.5);
            float age = spark.position.w + stage.seconds / life;
            float far = length(spark.position.xy);

            if (age >= 1.0 || journeys < 0.0 || far > 2.6) {
                // Gone: set out again from its strand's place on the rim.
                age = journeys < 0.0 ? spark.position.w : fract(age);
                journeys = max(journeys, 0.0) + 1.0;
                float strands = max(stage.controls[tendril_strands], 6.0);
                float strand = floor(own * strands);
                // Strands aren't evenly spaced: they bunch a little, as hair does.
                float round = (strand + 0.5 * chance(strand * 12.9898)) / strands;
                float angle = round * 6.2832 + stage.controls[tendril_turned];
                float2 heading = float2(cos(angle), sin(angle));
                spark.position.xy = heading * hole * (1.01 + 0.03 * chance2(own * 5.3, journeys));
                spark.position.z = 0.0;
                spark.velocity.w = mix(3.2, 6.5, chance(strand * 78.233));
                // The bands take turns round the hole, three sprays each.
                spark.nature.x = floor(fract(round * 3.0) * 6.0);
                // Some strands are bright and most are faint, so that the brighter
                // ones stand out as separate lines with darker gaps between.
                float strength = chance(strand * 39.346);
                spark.nature.z = mix(0.18, 2.4, strength * strength * strength);
                far = hole;
            }

            // Outward, faster as its band gets louder and when the bass pushes; and
            // bent by the current, more the further out it is.
            int band = clamp(int(spark.nature.x), 0, 5);
            float2 outward = spark.position.xy / max(far, 0.001);
            float speed = stage.controls[tendril_speed]
                * (0.55 + 0.75 * stage.bands[band] + 0.6 * stage.controls[tendril_push]);
            float2 current = tendrilCurrent(spark.position.xy, stage.time, stage.controls[tendril_curlSize]);
            float bent = smoothstep(hole, hole + 0.6, far);
            float2 velocity = outward * speed + current * stage.controls[tendril_curl] * bent * (0.6 + far);
            spark.velocity.xy = velocity;
            spark.position.xy += velocity * stage.seconds;

            // How it looks: its band's colour, fading in off the rim and out with age.
            float3 colour = bandLightOf(stage, band);
            // (Where they leave the rim the strands are packed tightest. Fading them in
            // keeps the rim from glaring, which would spill light into the hole.)
            float fade = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.55, 1.0, age));
            bool isSpeck = chance(own * 47.9 + journeys) < stage.controls[tendril_specks];
            float bright = stage.controls[tendril_sparkLight] * fade * (0.45 + 0.9 * stage.bands[band])
                * spark.nature.z;
            float size = 0.0015 * stage.controls[tendril_thickness];
            if (isSpeck) {
                // A speck: paler, bigger, far brighter, and twinkling.
                colour = mix(colour, float3(1.0), 0.6);
                float twinkle = 1.0 + stage.controls[tendril_twinkle]
                    * sin(stage.time * (3.0 + 9.0 * chance(own * 17.3)) + own * 200.0);
                bright *= 26.0 * max(twinkle, 0.1);
                size *= 2.2;
            }
            spark.look = float4(colour * bright, size);
            spark.position.w = age;
            spark.nature.y = journeys;
            sparks[index] = spark;
        }

        vertex SparkOut tendrilSpark(const device TendrilSpark *sparks [[buffer(0)]],
                                     constant StageUniforms &stage [[buffer(1)]],
                                     uint id [[vertex_id]]) {
            TendrilSpark spark = sparks[id];
            if (spark.nature.y < 0.0) return noSpark();
            // Drawn from where it was last frame to where it is now, so that one
            // frame's mark joins the next and the trail has no gaps.
            float3 before = spark.position.xyz - float3(spark.velocity.xy, 0.0) * stage.seconds;
            return makeSpark(stage, spark.position.xyz, before, spark.look.w, spark.look.rgb);
        }

        // Dims the last frame: a little everywhere, and to nothing inside the hole.
        fragment half4 tendrilDim(ScreenOut in [[stage_in]], constant StageUniforms &stage [[buffer(1)]]) {
            float2 fromHole = (in.uv - float2(stage.controls[tendril_holeX], stage.controls[tendril_holeY]))
                * float2(stage.aspect, 1.0);
            float radius = stage.controls[tendril_holeRadius];
            float outside = smoothstep(radius * 0.94, radius * 1.0, length(fromHole));
            return half4(half3(stage.controls[tendril_kept] * outside), 1.0h);
        }
        """
}
