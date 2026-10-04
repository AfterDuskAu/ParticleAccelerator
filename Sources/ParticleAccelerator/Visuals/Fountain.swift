import Foundation
import Metal
import simd

/// Visualizer 5, Fountain (docs/VISUALS.md): a white-hot point at the bottom, with
/// sparks of every colour spraying up in a widening cone and a soft glow on the floor.
///
/// With the music:
/// - The louder the song, the higher the spray and the more sparks in it.
/// - Each kick throws a burst.
/// - Each spark is a band's colour. The stronger a band is as a spark is thrown, the
///   more of the sparks are its colour, so the spray's colours show what's playing.
/// - The highs make the sparks twinkle, and the glow on the floor pulses.
///
/// The owner tuned its base design and locked it in on 2026-10-04 (`standard`).
/// Visualizer 8 (`Jets`) is the copy that carries on from it.
final class Fountain: Visual {
    static let number = 5

    private static let background = MTLClearColor(red: 0.0008, green: 0.0008, blue: 0.0016, alpha: 1)
    /// The sparks' brightness is set for this many. With more, each is dimmer, so a
    /// higher quality gives a finer picture and not a brighter one.
    private static let sparksTheBrightnessIsSetFor: Float = 150_000

    private var loudness = LiveSignal(
        SignalChain(source: .loudness, shape: SignalShape(low: 0.1, high: 1, steepness: 1.2, riseSeconds: 0.03, fallSeconds: 0.3)))
    private var burst = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.14)))
    private var sparkle = LiveSignal(
        SignalChain(source: .air, shape: SignalShape(low: 0.2, high: 1, steepness: 1.2, riseSeconds: 0.02, fallSeconds: 0.18)))
    private var punch = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.28)))
    private var bandLevels = Band.allCases.map { band in
        LiveSignal(SignalChain(source: band.source, shape: SignalShape(riseSeconds: 0.03, fallSeconds: 0.25)))
    }
    private let usualDrift = CameraDrift()

    private let device: MTLDevice
    private let moveSparks: MTLComputePipelineState
    private let drawSparks: MTLRenderPipelineState
    private let drawGlows: MTLRenderPipelineState
    private var sparks: MTLBuffer
    private var sparkCount: Int

    init(device: MTLDevice, library: MTLLibrary, particleCount: Int) throws {
        self.device = device
        guard let step = library.makeFunction(name: "fountainMoveSparks") else {
            throw StageProblem(message: "A shader is missing: fountainMoveSparks.")
        }
        moveSparks = try device.makeComputePipelineState(function: step)
        drawSparks = try device.makeLightPipeline(
            library: library, vertex: "fountainSpark", fragment: "sparkLight")
        drawGlows = try device.makeLightPipeline(
            library: library, vertex: "fountainGlow", fragment: "fountainGlowLight")
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
        uniforms.beat = kick
        for band in Band.allCases {
            uniforms.bands[band.rawValue] = bandLevels[band.rawValue].update(reading, seconds: seconds)
        }

        let drift = Control.common.drift(from: usualDrift, values: values)
        let camera = drift.camera(
            at: Double(uniforms.time), aspect: uniforms.aspect,
            punchNow: punch.update(reading, seconds: seconds) * reading.loudness)
        uniforms.viewProjection = camera.viewProjection
        uniforms.cameraPosition = SIMD4(camera.position, 0)
        uniforms.tanHalfFieldOfView = tan(camera.fieldOfView / 2)
        uniforms.focusDistance = drift.distance
        // Sparks nearer or further than the middle of the spray go a little soft.
        uniforms.blurPerUnit = 0.008
        uniforms.fog = 0
        Control.common.finish(&finishing, values: values)

        var numbers = SIMD32<Float>(repeating: 0)
        func put(_ number: Float, in slot: Slot) { numbers[slot.rawValue] = number }
        // How many of the waiting sparks are thrown up each second: a trickle in
        // silence, most of them when it's loud, and a burst on each kick.
        put(value(Control.amount) * (0.03 + 0.8 * loud * loud) + 1.6 * kick, in: .flow)
        // How fast they leave: fast enough at full loudness to reach the top of the
        // picture.
        put(value(Control.height) * (0.85 + 1.15 * loud) * (1 + 0.22 * min(kick, 1.5)), in: .speed)
        put(0.34 * value(Control.spread), in: .spread)
        put(0.95 * value(Control.gravity), in: .gravity)
        put(value(Control.life), in: .life)
        put(value(Control.sparkSize), in: .sparkSize)
        put(
            Self.sparksTheBrightnessIsSetFor / Float(max(sparkCount, 1)) * value(Control.sparkBrightness),
            in: .sparkLight)
        put((0.35 + 0.9 * sparkle.update(reading, seconds: seconds)) * value(Control.twinkle), in: .twinkle)
        put(value(Control.whiteHeat), in: .whiteHeat)
        put(value(Control.floorGlow) * (0.10 + 1.0 * loud + 0.9 * min(kick, 1.5)), in: .floorLight)
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

        // 2. The glow on the floor and at the mouth, then the sparks, as light.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = frame.picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = Self.background
        pass.colorAttachments[0].storeAction = .store
        guard let render = frame.commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        render.setVertexBytes(&uniforms, length: uniformsLength, index: 1)

        render.setRenderPipelineState(drawGlows)
        render.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 2)

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
                visual: Fountain.number, key: key, name: name, group: group, unit: unit, range: range,
                base: base, standard: Fountain.standard[key], spreadsEvenlyByRatio: byRatio, help: help)
        }

        static let common = CommonControls(visual: Fountain.number, standard: Fountain.standard)

        static let height = control(
            "height", "Height", "Spray", .times, 0.4...2, base: 1, byRatio: true,
            "How high the spray reaches. The louder the song, the higher it goes.")
        static let spread = control(
            "spread", "Spread", "Spray", .times, 0.2...3.5, base: 1, byRatio: true,
            "How wide the cone of sparks opens.")
        static let amount = control(
            "amount", "Amount", "Spray", .times, 0.2...4, base: 1, byRatio: true,
            "How many sparks are in the air. The louder the song, the more there are.")
        static let kickBurst = control(
            "kickBurst", "Kick burst", "Spray", .times, 0...4, base: 1,
            "How big a burst each kick throws.")
        static let gravity = control(
            "gravity", "Gravity", "Spray", .times, 0...3, base: 1,
            "How hard the sparks are pulled back down. At 0 they sail on upwards.")
        static let life = control(
            "life", "Life", "Spray", .times, 0.4...2.5, base: 1, byRatio: true,
            "How long each spark lasts before it fades.")

        static let sparkSize = control(
            "sparkSize", "Size", "Sparks", .times, 0.4...3, base: 1, byRatio: true,
            "How big each spark is.")
        static let sparkBrightness = control(
            "sparkBrightness", "Brightness", "Sparks", .times, 0.2...4, base: 1, byRatio: true,
            "How bright the sparks are.")
        static let twinkle = control(
            "twinkle", "Twinkle", "Sparks", .times, 0...2, base: 1,
            "How much the sparks flicker. The highs in the music add to it.")
        static let whiteHeat = control(
            "whiteHeat", "White heat", "Sparks", .share, 0...1, base: 0.14,
            "How far through its life a spark stays white-hot before it takes its colour.")

        static let floorGlow = control(
            "floorGlow", "Floor glow", "Floor", .times, 0...4, base: 1,
            "How bright the glow on the floor and at the mouth is. It pulses with the music.")
    }

    static let controls: [VisualControl] = [
        Control.height, Control.spread, Control.amount, Control.kickBurst, Control.gravity, Control.life,
        Control.sparkSize, Control.sparkBrightness, Control.twinkle, Control.whiteHeat, Control.common.streaks,
        Control.floorGlow,
        Control.common.cameraMovement, Control.common.beatPunch,
        Control.common.glow, Control.common.brightness, Control.common.darkCorners,
    ]

    /// The owner's standard (2026-10-04, "lock in visualizer 5"): a wide, quick spray
    /// of fewer, brighter sparks, a camera that moves a lot, and colours that change
    /// by themselves. Anything not listed is at its base.
    static let standard: [String: Float] = [
        "height": 1.37, "spread": 3.5, "amount": 0.43, "kickBurst": 1.67, "gravity": 3, "life": 2.03,
        "sparkBrightness": 2.74, "twinkle": 1.93,
        "cameraMovement": 4, "beatPunch": 1.41,
        "glow": 0.24, "brightness": 0.44, "darkCorners": 0.64,
        BandPalette.changesKey: 1, BandPalette.secondsKey: 4.68,
    ]
    /// The owner has settled it. Its panel starts locked, and can be unlocked.
    static let startsLocked = true

    // MARK: The sparks

    /// One spark, as the graphics card keeps it: 64 bytes.
    struct Spark {
        /// x, y, z, and its age from 0 (thrown) to 1 (gone, and waiting to be thrown
        /// again).
        var position: SIMD4<Float>
        /// How fast it's going each way, and how many seconds it lasts.
        var velocity: SIMD4<Float>
        /// x: its band. y: how many times it's been thrown. z: spare. w: its own
        /// unchanging number from 0 to 1.
        var nature: SIMD4<Float>
        /// Its light (its colour times its brightness) and its size on the stage.
        var look: SIMD4<Float>
    }

    /// Every spark waiting at the mouth. The same every time, so tests see the same
    /// picture.
    static func startingSparks(count: Int) -> [Spark] {
        (0..<count).map { index in
            let number = Float(((Double(index) + 0.5) * 0.618_033_988_749_895).truncatingRemainder(dividingBy: 1))
            return Spark(
                position: SIMD4(0, -10, 0, 1), velocity: SIMD4(0, 0, 0, 1), nature: SIMD4(0, 0, 0, number),
                look: .zero)
        }
    }

    // MARK: The shaders

    /// Where each number sits among the uniforms' `controls`. The shaders are given the
    /// same names ("fountain_speed").
    private enum Slot: Int, CaseIterable {
        /// How many of the waiting sparks are thrown each second, how fast, and how
        /// wide (the cone's half-angle).
        case flow, speed, spread
        case gravity, life, sparkSize, sparkLight, twinkle, whiteHeat, floorLight, shutter
    }

    private static let slotsSource = Slot.allCases
        .map { "constant int fountain_\($0) = \($0.rawValue);" }
        .joined(separator: "\n")

    static let shaderSource = """
        struct FountainSpark {
            float4 position;   // x, y, z, and age from 0 (thrown) to 1 (gone and waiting)
            float4 velocity;   // how fast it's going each way, and how many seconds it lasts
            float4 nature;     // its band, times thrown, spare, its own number
            float4 look;       // its light (colour times brightness), and its size on the stage
        };

        \(slotsSource)

        // Where the sparks come from: the middle of the floor, near the bottom of the
        // picture.
        constant float3 fountainMouth = float3(0.0, -0.80, 0.0);

        // Moves every spark on by one frame.
        kernel void fountainMoveSparks(device FountainSpark *sparks [[buffer(0)]],
                                       constant StageUniforms &stage [[buffer(1)]],
                                       constant uint &count [[buffer(2)]],
                                       uint index [[thread_position_in_grid]]) {
            if (index >= count) return;
            FountainSpark spark = sparks[index];
            float own = spark.nature.w;
            float thrown = spark.nature.y;
            float age = spark.position.w;

            if (age >= 1.0) {
                // Waiting at the mouth. Each frame some of those waiting are thrown.
                spark.look = float4(0.0);
                if (chance2(own * 91.7 + thrown * 0.618, stage.time * 7.31)
                        < stage.controls[fountain_flow] * stage.seconds) {
                    thrown += 1.0;
                    age = 0.0;
                    // Upwards, leaning out by a random amount in a random direction.
                    // More lean a little, fewer lean a lot.
                    float turn = chance2(own * 3.1, thrown) * 6.2832;
                    float lean = chance2(own * 5.3, thrown);
                    lean = lean * sqrt(lean) * stage.controls[fountain_spread];
                    float speed = stage.controls[fountain_speed] * mix(0.5, 1.0, chance2(own * 7.7, thrown));
                    spark.velocity.xyz = speed * float3(sin(lean) * cos(turn), cos(lean), sin(lean) * sin(turn));
                    spark.velocity.w = stage.controls[fountain_life] * mix(1.5, 3.2, chance2(own * 11.3, thrown));
                    spark.position.xyz = fountainMouth
                        + float3(cos(turn), 0.0, sin(turn)) * 0.012 * chance2(own * 13.9, thrown);

                    // Its band: the stronger a band is now, the likelier it is.
                    float all = 0.0;
                    for (int band = 0; band < 6; band++) all += 0.12 + stage.bands[band];
                    float pick = chance2(own * 17.1, thrown) * all;
                    float sum = 0.0;
                    spark.nature.x = 5.0;
                    for (int band = 0; band < 6; band++) {
                        sum += 0.12 + stage.bands[band];
                        if (pick < sum) { spark.nature.x = float(band); break; }
                    }
                }
            } else {
                age += stage.seconds / max(spark.velocity.w, 0.1);
                // Pulled down, slowed by the air, and never through the floor.
                spark.velocity.y -= stage.controls[fountain_gravity] * stage.seconds;
                spark.velocity.xyz *= exp(-0.35 * stage.seconds);
                spark.position.xyz += spark.velocity.xyz * stage.seconds;
                if (spark.position.y < fountainMouth.y) {
                    spark.position.y = fountainMouth.y;
                    spark.velocity.xyz *= float3(0.5, -0.25, 0.5);
                }

                // How it looks. White-hot as it leaves, then its band's colour.
                int band = clamp(int(spark.nature.x), 0, 5);
                float3 colour = mix(bandLightOf(stage, band), float3(1.0), 0.15);
                float hot = 1.0 - smoothstep(0.0, max(stage.controls[fountain_whiteHeat], 0.001), age);
                colour = mix(colour, float3(1.0, 0.96, 0.90), hot);
                float fade = smoothstep(0.0, 0.03, age) * (1.0 - smoothstep(0.55, 1.0, age));
                float twinkle = 1.0 + stage.controls[fountain_twinkle]
                    * sin(stage.time * (3.0 + 11.0 * chance(own * 17.3)) + own * 200.0);
                // One spark in five is bright enough to be seen by itself.
                bool bright1in5 = chance(own * 47.9) > 0.8;
                float bright = (bright1in5 ? 7.0 : 0.7) * stage.controls[fountain_sparkLight];
                bright *= fade * max(twinkle, 0.1) * (1.0 + 0.8 * hot);
                // The bass's sparks are the biggest.
                float tiny = chance(own * 31.1);
                float size = mix(0.0022, 0.0050, tiny * tiny) * (1.3 - 0.09 * float(band));
                spark.look = float4(colour * bright, size * stage.controls[fountain_sparkSize]);
            }

            spark.position.w = age;
            spark.nature.y = thrown;
            sparks[index] = spark;
        }

        vertex SparkOut fountainSpark(const device FountainSpark *sparks [[buffer(0)]],
                                      constant StageUniforms &stage [[buffer(1)]],
                                      uint id [[vertex_id]]) {
            FountainSpark spark = sparks[id];
            if (spark.position.w >= 1.0) return noSpark();
            float3 before = spark.position.xyz - spark.velocity.xyz * stage.controls[fountain_shutter];
            return makeSpark(stage, spark.position.xyz, before, spark.look.w, spark.look.rgb);
        }

        struct FountainGlowOut {
            float4 position [[position]];
            float2 within;   // -1 to 1 across the glow each way
            half3 light;
            float isMouth;
        };

        // Two glows, each a flat patch of light: one lying on the floor, and one
        // standing at the mouth where the sparks are white-hot.
        vertex FountainGlowOut fountainGlow(constant StageUniforms &stage [[buffer(1)]],
                                            uint id [[vertex_id]], uint which [[instance_id]]) {
            float2 corner = float2((id & 1u) != 0u ? 1.0 : -1.0, (id & 2u) != 0u ? 1.0 : -1.0);
            float3 place = which == 0u
                ? fountainMouth + float3(corner.x * 1.5, -0.01, corner.y * 0.8)
                : fountainMouth + float3(corner.x * 0.11, 0.13 + corner.y * 0.16, 0.0);
            FountainGlowOut out;
            out.position = stage.viewProjection * float4(place, 1.0);
            out.within = corner;
            out.isMouth = float(which);
            float3 colour = which == 0u ? float3(0.62, 0.72, 1.0) : float3(1.0, 0.97, 0.92);
            out.light = half3(colour * stage.controls[fountain_floorLight]);
            return out;
        }

        fragment half4 fountainGlowLight(FountainGlowOut in [[stage_in]]) {
            float shape;
            if (in.isMouth > 0.5) {
                // Narrow, brightest at the bottom, fading upwards.
                float up = in.within.y * 0.5 + 0.5;
                shape = exp(-in.within.x * in.within.x * 14.0) * exp(-up * up * 9.0) * 2.4;
            } else {
                // A wide soft pool with a hot middle.
                float away = dot(in.within, in.within);
                shape = exp(-away * 5.5) * 0.35 + exp(-away * 90.0) * 1.6;
            }
            return half4(in.light * half(shape), 1.0h);
        }
        """
}
