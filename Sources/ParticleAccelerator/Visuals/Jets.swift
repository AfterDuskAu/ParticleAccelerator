import Foundation
import Metal
import simd

/// Visualizer 8, Jets (docs/VISUALS.md): Visualizer 5's fountain, split into a row of
/// jets across the floor. Each band has jets of its own, in its own colour, in the
/// sound check's order: sub on the left to air on the right.
///
/// With the music:
/// - Each jet follows its own bars of the spectrum and nothing else. It stands as
///   tall as they are loud, and throws more sparks the louder they are.
/// - A fresh hit stands taller than a sound that holds, so beats show in a busy song.
/// - The sparks rise and fall quickly, so a jet is up within a beat and down before
///   the next.
/// - On each beat the kick's jets jump higher.
/// - The highs make the sparks twinkle.
///
/// The owner asked for this on 2026-10-04, as a copy of Visualizer 5 made "a lot more
/// responsive to their specific bars": in one fountain, with every band's sparks
/// thrown together to the loudness of the whole song, "it feels kind of chaotic".
final class Jets: Visual {
    static let number = 8

    private static let background = MTLClearColor(red: 0.0008, green: 0.0008, blue: 0.0016, alpha: 1)
    /// The sparks' brightness is set for this many. With more, each is dimmer, so a
    /// higher quality gives a finer picture and not a brighter one.
    private static let sparksTheBrightnessIsSetFor: Float = 150_000
    /// The most jets a band can have, and so the most there can be: 48 of the
    /// uniforms' 64 bars.
    static let mostJetsForABand = 8
    /// How high a jet reaches at its loudest, on the stage, before the person's
    /// "Height": from the floor to a little above the middle of the picture.
    private static let fullHeight: Float = 1.3
    /// How hard the sparks are pulled down, before the person's "Quickness". At this,
    /// a full jet's sparks are at the top in under half a second.
    private static let gravity: Float = 12
    /// A jet's part of the music counts for this much even in silence, so every jet
    /// keeps a simmer of sparks at its mouth.
    private static let simmer: Float = 0.04

    private var mountains = ParticleWave.Mountains()
    private var burst = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.14)))
    private var sparkle = LiveSignal(
        SignalChain(source: .air, shape: SignalShape(low: 0.2, high: 1, steepness: 1.2, riseSeconds: 0.02, fallSeconds: 0.18)))
    private var punch = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.28)))
    private let usualDrift = CameraDrift()

    private let device: MTLDevice
    private let moveSparks: MTLComputePipelineState
    private let drawSparks: MTLRenderPipelineState
    private let drawGlows: MTLRenderPipelineState
    private var sparks: MTLBuffer
    private var sparkCount: Int
    /// How many jets there were last frame, to draw a glow at each one's mouth.
    private var jetCount = 6

    init(device: MTLDevice, library: MTLLibrary, particleCount: Int) throws {
        self.device = device
        guard let step = library.makeFunction(name: "jetsMoveSparks") else {
            throw StageProblem(message: "A shader is missing: jetsMoveSparks.")
        }
        moveSparks = try device.makeComputePipelineState(function: step)
        drawSparks = try device.makeLightPipeline(
            library: library, vertex: "jetsSpark", fragment: "sparkLight")
        drawGlows = try device.makeLightPipeline(
            library: library, vertex: "jetsGlow", fragment: "jetsGlowLight")
        sparkCount = particleCount
        sparks = try device.makePrivateBuffer(of: Self.startingSparks(count: particleCount), called: "sparks")
    }

    func setParticleCount(_ count: Int) throws {
        guard count != sparkCount else { return }
        sparks = try device.makePrivateBuffer(of: Self.startingSparks(count: count), called: "sparks")
        sparkCount = count
    }

    // MARK: Each frame

    /// How strongly each jet's own bars are playing, from 0 to 1, jet by jet from the
    /// left: the tallest of the peaks over the bars the jet covers.
    static func jetLevels(peaks: SIMD64<Float>, jetsForEachBand: Int) -> [Float] {
        Band.allCases.flatMap { band in
            (0..<jetsForEachBand).map { part in
                BandSections.bars(ofPart: part, of: jetsForEachBand, in: band).map { peaks[$0] }.max() ?? 0
            }
        }
    }

    func prepare(
        _ uniforms: inout StageUniforms, finishing: inout FinishUniforms, reading: SoundReading,
        values: ControlValues
    ) {
        let seconds = Double(uniforms.seconds)
        func value(_ control: VisualControl) -> Float { values.value(of: control) }

        // Each jet's level, from its own bars.
        Control.response.apply(to: &mountains, values: values)
        let peaks = mountains.update(bars: reading.bars, seconds: seconds)
        let forEachBand = min(Self.mostJetsForABand, max(1, Int(value(Control.jetsForEachBand).rounded())))
        var levels = Self.jetLevels(peaks: peaks, jetsForEachBand: forEachBand)
        // On each beat the kick's jets jump higher.
        let kick = burst.update(reading, seconds: seconds) * value(Control.kickBurst)
        for jet in (Band.kick.rawValue * forEachBand)..<((Band.kick.rawValue + 1) * forEachBand) {
            levels[jet] = min(1.3, levels[jet] + 0.45 * kick)
        }
        jetCount = levels.count
        uniforms.bars = SIMD64<Float>(repeating: 0)
        for (jet, level) in levels.enumerated() { uniforms.bars[jet] = level }
        uniforms.loudness = reading.loudness
        uniforms.beat = kick

        let drift = Control.common.drift(from: usualDrift, values: values)
        let camera = drift.camera(
            at: Double(uniforms.time), aspect: uniforms.aspect,
            punchNow: punch.update(reading, seconds: seconds) * reading.loudness)
        uniforms.viewProjection = camera.viewProjection
        uniforms.cameraPosition = SIMD4(camera.position, 0)
        uniforms.tanHalfFieldOfView = tan(camera.fieldOfView / 2)
        uniforms.focusDistance = drift.distance
        // Sparks nearer or further than the row go a little soft.
        uniforms.blurPerUnit = 0.008
        uniforms.fog = 0
        Control.common.finish(&finishing, values: values)

        let quickness = value(Control.quickness)
        let allWeights = levels.reduce(0) { $0 + Self.simmer + $1 }
        var numbers = SIMD32<Float>(repeating: 0)
        func put(_ number: Float, in slot: Slot) { numbers[slot.rawValue] = number }
        put(Float(levels.count), in: .jets)
        put(Float(forEachBand), in: .forEachBand)
        put(allWeights, in: .allWeights)
        // How many of the waiting sparks are thrown each second: each jet throws by
        // how loud its own bars are, whatever the others are doing.
        put(value(Control.amount) * 1.6 * allWeights / Float(levels.count), in: .flow)
        // How fast a full jet's sparks leave, so that they top out at its height.
        put(quickness * (2 * Self.gravity * Self.fullHeight * value(Control.height)).squareRoot(), in: .speed)
        put(Self.gravity * quickness * quickness, in: .gravity)
        put(0.35 * quickness, in: .drag)
        put(1.12 * value(Control.rowWidth), in: .halfRow)
        put(0.07 * value(Control.spread), in: .spread)
        put(0.16 * value(Control.fan), in: .fan)
        put(value(Control.life), in: .life)
        put(value(Control.sparkSize), in: .sparkSize)
        put(
            Self.sparksTheBrightnessIsSetFor / Float(max(sparkCount, 1)) * value(Control.sparkBrightness),
            in: .sparkLight)
        put((0.35 + 0.9 * sparkle.update(reading, seconds: seconds)) * value(Control.twinkle), in: .twinkle)
        put(value(Control.whiteHeat), in: .whiteHeat)
        put(value(Control.floorGlow), in: .floorLight)
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

        // 2. The glow along the floor and at each jet's mouth, then the sparks, as
        // light.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = frame.picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = Self.background
        pass.colorAttachments[0].storeAction = .store
        guard let render = frame.commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        render.setVertexBytes(&uniforms, length: uniformsLength, index: 1)

        render.setRenderPipelineState(drawGlows)
        render.drawPrimitives(
            type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: jetCount + 1)

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
                visual: Jets.number, key: key, name: name, group: group, unit: unit, range: range,
                base: base, standard: Jets.standard[key], spreadsEvenlyByRatio: byRatio, help: help)
        }

        static let common = CommonControls(visual: Jets.number, standard: Jets.standard)
        static let response = ResponseControls(visual: Jets.number, standard: Jets.standard)

        static let jetsForEachBand = control(
            "jetsForEachBand", "Jets for each band", "Jets", .count, 1...Float(Jets.mostJetsForABand), base: 3,
            "How many jets each band has. With more, each follows a narrower part of its band.")
        static let height = control(
            "height", "Height", "Jets", .times, 0.4...2, base: 1, byRatio: true,
            "How high a jet reaches when its part of the music is at its loudest.")
        static let quickness = control(
            "quickness", "Quickness", "Jets", .times, 0.4...3, base: 1, byRatio: true,
            "How fast the sparks rise and fall. Higher follows the music more closely; lower lets them hang in the air.")
        static let rowWidth = control(
            "rowWidth", "Row width", "Jets", .times, 0.3...1.6, base: 1,
            "How far the row of jets spreads across the floor.")
        static let spread = control(
            "spread", "Spread", "Jets", .times, 0.2...6, base: 1, byRatio: true,
            "How wide each jet's cone of sparks opens. Narrow keeps the jets apart; wide runs them together.")
        static let fan = control(
            "fan", "Fan", "Jets", .times, 0...5, base: 1,
            "How much the jets lean outward from the middle, like a fan. At 0 they all stand straight up.")
        static let amount = control(
            "amount", "Amount", "Jets", .times, 0.2...4, base: 1, byRatio: true,
            "How many sparks are in the air. The louder a jet's part of the music, the more it throws.")
        static let kickBurst = control(
            "kickBurst", "Kick burst", "Jets", .times, 0...4, base: 1,
            "How much higher the kick's jets jump on each beat.")
        static let life = control(
            "life", "Life", "Jets", .times, 0.4...2.5, base: 1, byRatio: true,
            "How long each spark lasts. At 1 it fades as it lands; higher lets it bounce along the floor.")

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
            "How bright the glow along the floor and at each jet's mouth is. Each mouth glows with its own part of the music.")
    }

    static let controls: [VisualControl] =
        [
            Control.jetsForEachBand, Control.height, Control.quickness, Control.rowWidth, Control.spread,
            Control.fan, Control.amount, Control.kickBurst, Control.life,
        ] + Control.response.all + [
            Control.sparkSize, Control.sparkBrightness, Control.twinkle, Control.whiteHeat, Control.common.streaks,
            Control.floorGlow,
            Control.common.cameraMovement, Control.common.beatPunch,
            Control.common.glow, Control.common.brightness, Control.common.darkCorners,
        ]

    /// The owner's standard (2026-10-04). It began as their Visualizer 5's of that
    /// morning, and that afternoon they tuned it for itself: eight jets for each band,
    /// in a narrow row fanned wide; many small, twinkling sparks that rise and fall
    /// slowly, last long and leave long streaks; no glow on the floor; a camera that
    /// hardly moves; a darker picture with less glow; and colours that change by
    /// themselves. Anything not listed is at its base.
    static let standard: [String: Float] = [
        "jetsForEachBand": 8, "height": 1.17, "quickness": 0.51, "rowWidth": 0.60, "spread": 3.05,
        "fan": 4.21, "amount": 3.74, "kickBurst": 1.22, "life": 2.5,
        "sparkSize": 0.61, "sparkBrightness": 1.43, "twinkle": 2, "whiteHeat": 0.047, "streaks": 4,
        "floorGlow": 0,
        "cameraMovement": 0.24, "beatPunch": 0.17,
        "glow": 0.24, "brightness": 0.44, "darkCorners": 0.64,
        BandPalette.changesKey: 1, BandPalette.secondsKey: 4.68,
    ]

    // MARK: The sparks

    /// One spark, as the graphics card keeps it: 64 bytes.
    struct Spark {
        /// x, y, z, and its age from 0 (thrown) to 1 (gone, and waiting to be thrown
        /// again).
        var position: SIMD4<Float>
        /// How fast it's going each way, and how many seconds it lasts.
        var velocity: SIMD4<Float>
        /// x: its jet, counting from the left. y: how many times it's been thrown.
        /// z: spare. w: its own unchanging number from 0 to 1.
        var nature: SIMD4<Float>
        /// Its light (its colour times its brightness) and its size on the stage.
        var look: SIMD4<Float>
    }

    /// Every spark waiting to be thrown. The same every time, so tests see the same
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
    /// same names ("jets_speed"). Each jet's level is in the uniforms' `bars`, jet by
    /// jet from the left.
    private enum Slot: Int, CaseIterable {
        /// How many jets there are, how many each band has, and what all their
        /// levels come to (with the simmer), for sharing the sparks out.
        case jets, forEachBand, allWeights
        /// How many of the waiting sparks are thrown each second, and how fast a full
        /// jet's leave.
        case flow, speed
        case gravity, drag, halfRow, spread, fan, life
        case sparkSize, sparkLight, twinkle, whiteHeat, floorLight, shutter
    }

    private static let slotsSource = Slot.allCases
        .map { "constant int jets_\($0) = \($0.rawValue);" }
        .joined(separator: "\n")

    static let shaderSource = """
        struct JetsSpark {
            float4 position;   // x, y, z, and age from 0 (thrown) to 1 (gone and waiting)
            float4 velocity;   // how fast it's going each way, and how many seconds it lasts
            float4 nature;     // its jet, times thrown, spare, its own number
            float4 look;       // its light (colour times brightness), and its size on the stage
        };

        \(slotsSource)

        // The floor the jets stand on, near the bottom of the picture.
        constant float jetsFloor = -0.80;
        // A jet's part of the music counts for this much even in silence.
        constant float jetsSimmer = \(simmer);

        // Where a jet's mouth is along the row.
        static float jetsMouth(constant StageUniforms &stage, int jet) {
            float along = (float(jet) + 0.5) / max(stage.controls[jets_jets], 1.0);
            return (along * 2.0 - 1.0) * stage.controls[jets_halfRow];
        }

        // Moves every spark on by one frame.
        kernel void jetsMoveSparks(device JetsSpark *sparks [[buffer(0)]],
                                   constant StageUniforms &stage [[buffer(1)]],
                                   constant uint &count [[buffer(2)]],
                                   uint index [[thread_position_in_grid]]) {
            if (index >= count) return;
            JetsSpark spark = sparks[index];
            float own = spark.nature.w;
            float thrown = spark.nature.y;
            float age = spark.position.w;
            int jets = clamp(int(stage.controls[jets_jets]), 1, 64);

            if (age >= 1.0) {
                // Waiting. Each frame some of those waiting are thrown.
                spark.look = float4(0.0);
                if (sparkChance(index, uint(stage.time * 6000.0))
                        < stage.controls[jets_flow] * stage.seconds) {
                    thrown += 1.0;
                    age = 0.0;
                    // Its numbers are different for each flight.
                    uint flight = uint(thrown) * 16u;

                    // Its jet: the louder a jet's own bars are now, the likelier it is.
                    float pick = sparkChance(index, flight) * stage.controls[jets_allWeights];
                    float sum = 0.0;
                    int jet = jets - 1;
                    for (int each = 0; each < jets; each++) {
                        sum += jetsSimmer + stage.bars[each];
                        if (pick < sum) { jet = each; break; }
                    }
                    spark.nature.x = float(jet);
                    float level = stage.bars[jet];

                    // Upwards, leaning out a little in a random direction, and with
                    // the whole jet leaning outward from the middle of the row.
                    float turn = sparkChance(index, flight + 1u) * 6.2832;
                    float lean = sparkChance(index, flight + 2u);
                    lean = lean * sqrt(lean) * stage.controls[jets_spread];
                    float3 heading = float3(sin(lean) * cos(turn), cos(lean), sin(lean) * sin(turn));
                    float mouth = jetsMouth(stage, jet);
                    float fanned = stage.controls[jets_fan] * mouth / max(stage.controls[jets_halfRow], 0.01);
                    heading.xy = float2(heading.x * cos(fanned) + heading.y * sin(fanned),
                                        heading.y * cos(fanned) - heading.x * sin(fanned));

                    // Fast enough to top out at the jet's level: a thing thrown twice
                    // as high leaves 1.4 times as fast.
                    float speed = stage.controls[jets_speed] * sqrt(max(level, 0.012))
                        * mix(0.78, 1.0, sparkChance(index, flight + 3u));
                    spark.velocity.xyz = heading * speed;
                    // It lasts about as long as it takes to go up and come down.
                    float flightSeconds = 2.0 * speed / max(stage.controls[jets_gravity], 0.01);
                    spark.velocity.w = max(0.25, flightSeconds * stage.controls[jets_life]
                        * mix(0.8, 1.05, sparkChance(index, flight + 4u)));
                    spark.position.xyz = float3(mouth, jetsFloor, 0.0)
                        + float3(cos(turn), 0.0, sin(turn)) * 0.012 * sparkChance(index, flight + 5u);
                }
            } else {
                age += stage.seconds / max(spark.velocity.w, 0.1);
                // Pulled down, slowed by the air, and never through the floor.
                spark.velocity.y -= stage.controls[jets_gravity] * stage.seconds;
                spark.velocity.xyz *= exp(-stage.controls[jets_drag] * stage.seconds);
                spark.position.xyz += spark.velocity.xyz * stage.seconds;
                if (spark.position.y < jetsFloor) {
                    spark.position.y = jetsFloor;
                    spark.velocity.xyz *= float3(0.5, -0.25, 0.5);
                }

                // How it looks. White-hot as it leaves, then its band's colour, and
                // brighter while its jet's own bars are loud.
                int jet = clamp(int(spark.nature.x), 0, jets - 1);
                int band = clamp(jet / max(int(stage.controls[jets_forEachBand]), 1), 0, 5);
                float3 colour = mix(bandLightOf(stage, band), float3(1.0), 0.12);
                float hot = 1.0 - smoothstep(0.0, max(stage.controls[jets_whiteHeat], 0.001), age);
                colour = mix(colour, float3(1.0, 0.96, 0.90), hot);
                float fade = smoothstep(0.0, 0.03, age) * (1.0 - smoothstep(0.6, 1.0, age));
                float twinkle = 1.0 + stage.controls[jets_twinkle]
                    * sin(stage.time * (3.0 + 11.0 * chance(own * 17.3)) + own * 200.0);
                // One spark in five is bright enough to be seen by itself.
                bool bright1in5 = chance(own * 47.9) > 0.8;
                float bright = (bright1in5 ? 7.0 : 0.7) * stage.controls[jets_sparkLight];
                bright *= fade * max(twinkle, 0.1) * (1.0 + 0.8 * hot) * (0.55 + 0.9 * stage.bars[jet]);
                // The bass's sparks are the biggest.
                float tiny = chance(own * 31.1);
                float size = mix(0.0022, 0.0050, tiny * tiny) * (1.3 - 0.09 * float(band));
                spark.look = float4(colour * bright, size * stage.controls[jets_sparkSize]);
            }

            spark.position.w = age;
            spark.nature.y = thrown;
            sparks[index] = spark;
        }

        vertex SparkOut jetsSpark(const device JetsSpark *sparks [[buffer(0)]],
                                  constant StageUniforms &stage [[buffer(1)]],
                                  uint id [[vertex_id]]) {
            JetsSpark spark = sparks[id];
            if (spark.position.w >= 1.0) return noSpark();
            float3 before = spark.position.xyz - spark.velocity.xyz * stage.controls[jets_shutter];
            return makeSpark(stage, spark.position.xyz, before, spark.look.w, spark.look.rgb);
        }

        struct JetsGlowOut {
            float4 position [[position]];
            float2 within;   // -1 to 1 across the glow each way
            half3 light;
            float isMouth;
        };

        // The glows, each a flat patch of light: one lying along the floor under the
        // whole row, and one standing at each jet's mouth, in its band's colour and as
        // bright as its own bars are loud.
        vertex JetsGlowOut jetsGlow(constant StageUniforms &stage [[buffer(1)]],
                                    uint id [[vertex_id]], uint which [[instance_id]]) {
            float2 corner = float2((id & 1u) != 0u ? 1.0 : -1.0, (id & 2u) != 0u ? 1.0 : -1.0);
            JetsGlowOut out;
            out.within = corner;
            float3 place;
            float3 colour;
            if (which == 0u) {
                float reach = stage.controls[jets_halfRow] + 0.9;
                place = float3(corner.x * reach, jetsFloor - 0.01, corner.y * 0.8);
                colour = float3(0.50, 0.62, 1.0) * (0.02 + 0.22 * stage.loudness);
                out.isMouth = 0.0;
            } else {
                int jet = int(which) - 1;
                float level = stage.bars[jet];
                int band = clamp(jet / max(int(stage.controls[jets_forEachBand]), 1), 0, 5);
                place = float3(jetsMouth(stage, jet) + corner.x * 0.07, jetsFloor + 0.10 + corner.y * 0.13, 0.0);
                colour = mix(bandLightOf(stage, band), float3(1.0, 0.97, 0.92), 0.45) * (0.05 + 1.3 * level);
                out.isMouth = 1.0;
            }
            out.position = stage.viewProjection * float4(place, 1.0);
            out.light = half3(colour * stage.controls[jets_floorLight]);
            return out;
        }

        fragment half4 jetsGlowLight(JetsGlowOut in [[stage_in]]) {
            float shape;
            if (in.isMouth > 0.5) {
                // Narrow, brightest at the bottom, fading upwards.
                float up = in.within.y * 0.5 + 0.5;
                shape = exp(-in.within.x * in.within.x * 14.0) * exp(-up * up * 9.0) * 2.4;
            } else {
                // A long soft pool, fading towards its ends and its edges.
                shape = exp(-in.within.y * in.within.y * 5.5) * (1.0 - in.within.x * in.within.x) * 0.5;
            }
            return half4(in.light * half(shape), 1.0h);
        }
        """
}
