import Foundation
import Metal
import simd

/// Visualizer 6, Starburst (docs/VISUALS.md): sparks fire off from a glowing centre in
/// every direction, like a firework that never stops going off. Each keeps flying
/// outward and fades on its way. Near sparks are big and blurred, far ones small and
/// sharp.
///
/// With the music:
/// - The louder the song, the more sparks fire and the faster they leave.
/// - Each kick throws a shell of them at once, a little faster than the rest.
/// - Each spark is a pale shade of a band's colour. The stronger a band is as a spark
///   fires, the more of the sparks are its colour and the faster they leave.
/// - The highs make the sparks twinkle. The centre glows with the loudness and pulses
///   on each kick.
///
/// This is its second base design (2026-10-04). The first fired streams on each kick:
/// straight lines of sparks behind a bright head, which flew out, stopped and faded
/// where they were. The owner asked for sparks that fire off from the centre without
/// those lines, and keep moving outward as they fade.
final class Starburst: Visual {
    static let number = 6

    private static let background = MTLClearColor(red: 0.0010, green: 0.0008, blue: 0.0030, alpha: 1)
    /// The sparks' brightness is set for this many. With more, each is dimmer, so a
    /// higher quality gives a finer picture and not a brighter one.
    private static let sparksTheBrightnessIsSetFor: Float = 150_000

    private var loudness = LiveSignal(
        SignalChain(source: .loudness, shape: SignalShape(low: 0.1, high: 1, steepness: 1.2, riseSeconds: 0.03, fallSeconds: 0.3)))
    private var burst = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.14)))
    private var sparkle = LiveSignal(
        SignalChain(source: .air, shape: SignalShape(low: 0.2, high: 1, steepness: 1.2, riseSeconds: 0.02, fallSeconds: 0.18)))
    private var corePulse = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.22)))
    private var punch = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.28)))
    private var bandLevels = Band.allCases.map { band in
        LiveSignal(SignalChain(source: band.source, shape: SignalShape(riseSeconds: 0.03, fallSeconds: 0.25)))
    }
    private let usualDrift = CameraDrift()
    /// How far the whole burst has turned, added up frame by frame, so a change of
    /// speed never makes it jump.
    private var turned: Float = 0

    private let device: MTLDevice
    private let moveSparks: MTLComputePipelineState
    private let drawSparks: MTLRenderPipelineState
    private let drawCore: MTLRenderPipelineState
    private var sparks: MTLBuffer
    private var sparkCount: Int

    init(device: MTLDevice, library: MTLLibrary, particleCount: Int) throws {
        self.device = device
        guard let step = library.makeFunction(name: "starMoveSparks") else {
            throw StageProblem(message: "A shader is missing: starMoveSparks.")
        }
        moveSparks = try device.makeComputePipelineState(function: step)
        drawSparks = try device.makeLightPipeline(
            library: library, vertex: "starSpark", fragment: "sparkLight")
        drawCore = try device.makeLightPipeline(
            library: library, vertex: "starCore", fragment: "starCoreLight")
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

        let loud = loudness.update(reading, seconds: seconds)
        let kick = burst.update(reading, seconds: seconds) * value(Control.kickBurst)
        uniforms.loudness = loud
        uniforms.beat = corePulse.update(reading, seconds: seconds)
        for band in Band.allCases {
            uniforms.bands[band.rawValue] = bandLevels[band.rawValue].update(reading, seconds: seconds)
        }
        turned += value(Control.turning) * 0.07 * uniforms.seconds

        let drift = Control.common.drift(from: usualDrift, values: values)
        let camera = drift.camera(
            at: Double(uniforms.time), aspect: uniforms.aspect,
            punchNow: punch.update(reading, seconds: seconds) * reading.loudness)
        uniforms.viewProjection = camera.viewProjection
        uniforms.cameraPosition = SIMD4(camera.position, 0)
        uniforms.tanHalfFieldOfView = tan(camera.fieldOfView / 2)
        uniforms.focusDistance = drift.distance
        // Sparks flying towards the camera go well out of focus.
        uniforms.blurPerUnit = 0.010 * value(Control.blur)
        uniforms.fog = 0
        Control.common.finish(&finishing, values: values)

        var numbers = SIMD32<Float>(repeating: 0)
        func put(_ number: Float, in slot: Slot) { numbers[slot.rawValue] = number }
        // How many of the waiting sparks fire each second: a trickle in silence, most
        // of them when it's loud, and a shell on each kick.
        put(value(Control.amount) * (0.04 + 0.55 * loud * loud) + 3.0 * kick, in: .flow)
        // How fast they leave: faster when it's loud, and the kick's shell faster
        // still, so that it runs out through the rest.
        put(1.25 * value(Control.speed) * (0.6 + 0.5 * loud) * (1 + 0.45 * min(kick, 1.5)), in: .speed)
        put(1.1 * value(Control.slowing), in: .slowing)
        put(0.10 * value(Control.droop), in: .droop)
        put(value(Control.life), in: .life)
        put(value(Control.brightFor), in: .brightFor)
        put(turned, in: .turned)
        put(value(Control.sparkSize), in: .sparkSize)
        put(
            Self.sparksTheBrightnessIsSetFor / Float(max(sparkCount, 1)) * value(Control.sparkBrightness),
            in: .sparkLight)
        put((0.3 + 0.9 * sparkle.update(reading, seconds: seconds)) * value(Control.twinkle), in: .twinkle)
        put(value(Control.whiteness), in: .whiteness)
        put(value(Control.centreGlow), in: .coreLight)
        put(Control.common.shutterSeconds(values: values), in: .shutter)
        uniforms.controls = numbers
    }

    func draw(_ frame: VisualFrame) {
        var uniforms = frame.uniforms
        let uniformsLength = MemoryLayout<StageUniforms>.stride
        var count = UInt32(sparkCount)

        // 1. The graphics card moves every spark.
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

        // 2. The glow at the centre, then the sparks, as light.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = frame.picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = Self.background
        pass.colorAttachments[0].storeAction = .store
        guard let render = frame.commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        render.setVertexBytes(&uniforms, length: uniformsLength, index: 1)

        render.setRenderPipelineState(drawCore)
        render.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

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
                visual: Starburst.number, key: key, name: name, group: group, unit: unit, range: range,
                base: base, standard: Starburst.standard[key], spreadsEvenlyByRatio: byRatio, help: help)
        }

        static let common = CommonControls(visual: Starburst.number, standard: Starburst.standard)

        static let amount = control(
            "amount", "Amount", "Burst", .times, 0.2...4, base: 1, byRatio: true,
            "How many sparks are in the air. The louder the song, the more of them fire.")
        // (Saved as "launchSpeed": the first design's "speed" was how fast a burst
        // opened, and a setting saved for that would send these sparks far too fast.)
        static let speed = control(
            "launchSpeed", "Speed", "Burst", .times, 0.3...3, base: 1, byRatio: true,
            "How fast the sparks leave the centre. The louder a spark's own part of the music, the faster it goes.")
        static let kickBurst = control(
            "kickBurst", "Kick burst", "Burst", .times, 0...4, base: 1,
            "How big a shell of sparks each kick throws.")
        static let life = control(
            "life", "Life", "Burst", .times, 0.4...2.5, base: 1, byRatio: true,
            "How long each spark flies before it has faded away.")
        static let slowing = control(
            "slowing", "Slowing", "Burst", .times, 0...4, base: 1,
            "How much the air slows the sparks. They never stop: they settle into a steady drift outward. At 0 they keep the speed they left with.")
        static let droop = control(
            "droop", "Droop", "Burst", .times, 0...6, base: 1,
            "How much the sparks sink as they fly, the way a firework's do. At 0 nothing pulls them down.")
        static let turning = control(
            "turning", "Turning", "Burst", .times, 0...6, base: 1,
            "How fast the whole burst turns.")

        static let sparkSize = control(
            "sparkSize", "Size", "Sparks", .times, 0.4...3, base: 1, byRatio: true,
            "How big each spark is.")
        static let sparkBrightness = control(
            "sparkBrightness", "Brightness", "Sparks", .times, 0.2...4, base: 1, byRatio: true,
            "How bright the sparks are.")
        static let brightFor = control(
            "brightFor", "Bright for", "Sparks", .share, 0...0.9, base: 0.2,
            "How far through its flight a spark stays at its brightest. After that it fades, and keeps flying outward as it does.")
        static let twinkle = control(
            "twinkle", "Twinkle", "Sparks", .times, 0...2, base: 1,
            "How much the sparks flicker. The highs in the music add to it.")
        static let whiteness = control(
            "whiteness", "Whiteness", "Sparks", .share, 0...1, base: 0.3,
            "How pale the sparks are. At 0 each is its band's full colour; at 100% they're all white.")
        static let blur = control(
            "blur", "Blur", "Sparks", .times, 0...3, base: 1,
            "How far out of focus the sparks nearest the camera go.")

        static let centreGlow = control(
            "centreGlow", "Centre glow", "Centre", .times, 0...4, base: 1,
            "How bright the glow at the centre is. It grows with the loudness and pulses on each kick.")
    }

    static let controls: [VisualControl] = [
        Control.amount, Control.speed, Control.kickBurst, Control.life, Control.slowing, Control.droop,
        Control.turning,
        Control.sparkSize, Control.sparkBrightness, Control.brightFor, Control.twinkle, Control.whiteness,
        Control.blur, Control.common.streaks,
        Control.centreGlow,
        Control.common.cameraMovement, Control.common.beatPunch,
        Control.common.glow, Control.common.brightness, Control.common.darkCorners,
    ]

    // MARK: The sparks

    /// One spark, as the graphics card keeps it: 64 bytes.
    struct Spark {
        /// x, y, z, and its age from 0 (fired) to 1 (gone, and waiting to be fired
        /// again).
        var position: SIMD4<Float>
        /// How fast it's going each way, and how many seconds it lasts.
        var velocity: SIMD4<Float>
        /// x: its band. y: how many times it's been fired. z: how fast it left.
        /// w: its own unchanging number from 0 to 1.
        var nature: SIMD4<Float>
        /// Its light (its colour times its brightness) and its size on the stage.
        var look: SIMD4<Float>
    }

    /// Every spark waiting at the centre. The same every time, so tests see the same
    /// picture.
    static func startingSparks(count: Int) -> [Spark] {
        (0..<count).map { index in
            let number = Float(((Double(index) + 0.5) * 0.618_033_988_749_895).truncatingRemainder(dividingBy: 1))
            return Spark(
                position: SIMD4(0, 0, 0, 1), velocity: SIMD4(0, 0, 0, 1), nature: SIMD4(0, 0, 0, number),
                look: .zero)
        }
    }

    // MARK: The shaders

    /// Where each number sits among the uniforms' `controls`. The shaders are given the
    /// same names ("star_speed").
    private enum Slot: Int, CaseIterable {
        /// How many of the waiting sparks fire each second, and how fast they leave.
        case flow, speed
        case slowing, droop, life, brightFor, turned
        case sparkSize, sparkLight, twinkle, whiteness, coreLight, shutter
    }

    private static let slotsSource = Slot.allCases
        .map { "constant int star_\($0) = \($0.rawValue);" }
        .joined(separator: "\n")

    static let shaderSource = """
        struct StarSpark {
            float4 position;   // x, y, z, and age from 0 (fired) to 1 (gone and waiting)
            float4 velocity;   // how fast it's going each way, and how many seconds it lasts
            float4 nature;     // its band, times fired, how fast it left, its own number
            float4 look;       // its light (colour times brightness), and its size on the stage
        };

        \(slotsSource)

        // However much the air slows a spark, it keeps this share of the speed it left
        // with, so it never stops.
        constant float starSpeedKept = 0.32;

        // Moves every spark on by one frame.
        kernel void starMoveSparks(device StarSpark *sparks [[buffer(0)]],
                                   constant StageUniforms &stage [[buffer(1)]],
                                   constant uint &count [[buffer(2)]],
                                   uint index [[thread_position_in_grid]]) {
            if (index >= count) return;
            StarSpark spark = sparks[index];
            float own = spark.nature.w;
            float fired = spark.nature.y;
            float age = spark.position.w;

            if (age >= 1.0) {
                // Waiting at the centre. Each frame some of those waiting are fired.
                spark.look = float4(0.0);
                if (sparkChance(index, uint(stage.time * 6000.0))
                        < stage.controls[star_flow] * stage.seconds) {
                    fired += 1.0;
                    age = 0.0;
                    // Its numbers are different for each flight.
                    uint flight = uint(fired) * 16u;

                    // Its band: the stronger a band is now, the likelier it is.
                    float all = 0.0;
                    for (int band = 0; band < 6; band++) all += 0.12 + stage.bands[band];
                    float pick = sparkChance(index, flight) * all;
                    float sum = 0.0;
                    int band = 5;
                    for (int each = 0; each < 6; each++) {
                        sum += 0.12 + stage.bands[each];
                        if (pick < sum) { band = each; break; }
                    }
                    spark.nature.x = float(band);

                    // Any direction, spread evenly over a ball. No two sparks share a
                    // line out from the centre.
                    float up = 1.0 - 2.0 * sparkChance(index, flight + 1u);
                    float round = 6.2832 * sparkChance(index, flight + 2u);
                    float flat = sqrt(max(0.0, 1.0 - up * up));
                    float3 heading = float3(flat * cos(round), up, flat * sin(round));
                    // Faster the stronger its band is, and no two quite alike.
                    float speed = stage.controls[star_speed] * (0.55 + 0.6 * stage.bands[band])
                        * mix(0.6, 1.0, sparkChance(index, flight + 3u));
                    spark.velocity.xyz = heading * speed;
                    spark.velocity.w = stage.controls[star_life] * mix(2.2, 3.6, sparkChance(index, flight + 4u));
                    spark.nature.z = speed;
                    spark.position.xyz = heading * 0.02;
                }
            } else {
                age += stage.seconds / max(spark.velocity.w, 0.1);
                // The air slows it towards a steady drift outward, and it sinks a
                // little, as a firework's sparks do. It never stops or turns back.
                float3 outward = normalize(spark.position.xyz);
                float3 drift = outward * spark.nature.z * starSpeedKept;
                spark.velocity.xyz += (drift - spark.velocity.xyz)
                    * (1.0 - exp(-stage.controls[star_slowing] * stage.seconds));
                spark.velocity.y -= stage.controls[star_droop] * stage.seconds;
                spark.position.xyz += spark.velocity.xyz * stage.seconds;

                // How it looks: a pale shade of its band's colour, white-hot as it
                // leaves. It's at its brightest for the first part of its flight and
                // fades over the rest.
                int band = clamp(int(spark.nature.x), 0, 5);
                float3 colour = mix(bandLightOf(stage, band), float3(0.86, 0.84, 1.0),
                                    stage.controls[star_whiteness]);
                float hot = 1.0 - smoothstep(0.0, 0.05, age);
                colour = mix(colour, float3(1.0, 0.97, 0.94), hot);
                float fading = smoothstep(stage.controls[star_brightFor], 1.0, age);
                float fade = smoothstep(0.0, 0.015, age) * (1.0 - fading) * (1.0 - fading);
                float twinkle = 1.0 + stage.controls[star_twinkle]
                    * sin(stage.time * (3.0 + 11.0 * chance(own * 17.3)) + own * 200.0);
                // One spark in five is bright enough to be seen by itself.
                bool bright1in5 = chance(own * 47.9) > 0.8;
                float bright = (bright1in5 ? 6.0 : 0.4) * stage.controls[star_sparkLight];
                bright *= fade * max(twinkle, 0.1) * (1.0 + 0.8 * hot);
                float tiny = chance(own * 31.1);
                float size = mix(0.0022, 0.0050, tiny * tiny) * (1.3 - 0.09 * float(band));
                spark.look = float4(colour * bright, size * stage.controls[star_sparkSize]);
            }

            spark.position.w = age;
            spark.nature.y = fired;
            sparks[index] = spark;
        }

        // The whole burst turns slowly.
        static float3 starTurned(constant StageUniforms &stage, float3 place) {
            float turned = stage.controls[star_turned];
            float2 swung = float2(cos(turned), sin(turned));
            return float3(place.x * swung.x + place.z * swung.y, place.y,
                          place.z * swung.x - place.x * swung.y);
        }

        vertex SparkOut starSpark(const device StarSpark *sparks [[buffer(0)]],
                                  constant StageUniforms &stage [[buffer(1)]],
                                  uint id [[vertex_id]]) {
            StarSpark spark = sparks[id];
            if (spark.position.w >= 1.0) return noSpark();
            float3 place = starTurned(stage, spark.position.xyz);
            // A spark about to fly past the camera fades away. Left alone it would
            // cover the picture as one huge disc for a frame or two, which shows as a
            // flicker and costs the graphics card dearly.
            float near = smoothstep(0.35, 1.0, distance(place, stage.cameraPosition.xyz));
            if (near <= 0.0) return noSpark();
            float3 before = spark.position.xyz - spark.velocity.xyz * stage.controls[star_shutter];
            return makeSpark(stage, place, starTurned(stage, before), spark.look.w, spark.look.rgb * near);
        }

        struct StarCoreOut {
            float4 position [[position]];
            float2 within;
            half3 light;
        };

        // The glow at the centre, which every spark comes out of. It swells on a kick.
        vertex StarCoreOut starCore(constant StageUniforms &stage [[buffer(1)]], uint id [[vertex_id]]) {
            float2 corner = float2((id & 1u) != 0u ? 1.0 : -1.0, (id & 2u) != 0u ? 1.0 : -1.0);
            float size = 0.22 + 0.10 * stage.beat;
            StarCoreOut out;
            // Flat to the camera.
            float4 middle = stage.viewProjection * float4(0.0, 0.0, 0.0, 1.0);
            out.position = middle;
            out.position.xy += corner * size * float2(1.0 / stage.aspect, 1.0) / stage.tanHalfFieldOfView;
            out.within = corner;
            float3 colour = mix(float3(0.80, 0.76, 1.0), float3(1.0), 0.3);
            out.light = half3(colour * (0.25 + 0.9 * stage.loudness + 1.6 * stage.beat)
                              * stage.controls[star_coreLight]);
            return out;
        }

        fragment half4 starCoreLight(StarCoreOut in [[stage_in]]) {
            float away = dot(in.within, in.within);
            float shape = exp(-away * 9.0) * 0.5 + exp(-away * 120.0) * 2.5;
            return half4(in.light * half(shape), 1.0h);
        }
        """
}
