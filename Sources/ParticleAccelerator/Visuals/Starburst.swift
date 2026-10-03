import Foundation
import Metal
import simd

/// Visualizer 6, Starburst (docs/VISUALS.md): streams of sparks shoot outward from a
/// centre in every direction, each led by a bright head. Near sparks are big and
/// blurred, far ones small and sharp.
///
/// With the music:
/// - Each kick fires a new burst. The last four are in the air together.
/// - The louder the song, the faster the streams and the more of them there are.
/// - Each stream belongs to a band and wears a pale shade of its colour. The stronger
///   the band, the further its streams reach.
/// - Between kicks a thin field of sparks drifts outward, faster when it's loud.
///
/// Nothing is kept from frame to frame: where a spark is follows from its number and
/// how long ago its kick landed. So there's nothing for the graphics card to move,
/// only to draw.
///
/// This is its base design (2026-10-04): the owner tunes it from here with its
/// controls.
final class Starburst: Visual {
    static let number = 6

    private static let background = MTLClearColor(red: 0.0010, green: 0.0008, blue: 0.0030, alpha: 1)
    /// The sparks' brightness is set for this many. With more, each is dimmer, so a
    /// higher quality gives a finer picture and not a brighter one.
    private static let sparksTheBrightnessIsSetFor: Float = 150_000

    private var loudness = LiveSignal(
        SignalChain(source: .loudness, shape: SignalShape(low: 0.1, high: 1, steepness: 1.2, riseSeconds: 0.05, fallSeconds: 0.4)))
    private var sparkle = LiveSignal(
        SignalChain(source: .air, shape: SignalShape(low: 0.2, high: 1, steepness: 1.2, riseSeconds: 0.02, fallSeconds: 0.18)))
    private var corePulse = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.22)))
    private var punch = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.28)))
    private var bandLevels = Band.allCases.map { band in
        LiveSignal(SignalChain(source: band.source, shape: SignalShape(riseSeconds: 0.03, fallSeconds: 0.35)))
    }
    private let usualDrift = CameraDrift()
    private var kicks = KickClock()
    /// How far the drifting field has travelled, and how far the whole burst has
    /// turned. They're added up frame by frame, so a change of speed never makes
    /// anything jump.
    private var travelled: Float = 0
    private var turned: Float = 0

    private let drawSparks: MTLRenderPipelineState
    private let drawCore: MTLRenderPipelineState
    private var sparkCount: Int

    init(device: MTLDevice, library: MTLLibrary, particleCount: Int) throws {
        drawSparks = try device.makeLightPipeline(
            library: library, vertex: "starSpark", fragment: "sparkLight")
        drawCore = try device.makeLightPipeline(
            library: library, vertex: "starCore", fragment: "starCoreLight")
        sparkCount = particleCount
    }

    func setParticleCount(_ count: Int) throws {
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
        uniforms.loudness = loud
        uniforms.beat = corePulse.update(reading, seconds: seconds)
        for band in Band.allCases {
            uniforms.bands[band.rawValue] = bandLevels[band.rawValue].update(reading, seconds: seconds)
        }
        uniforms.kickAges = kicks.ages(reading: reading, time: uniforms.time)

        let flowSpeed = value(Control.flow) * (0.03 + 0.35 * loud)
        travelled += flowSpeed * uniforms.seconds
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
        // The louder the song, the more streams fire and the faster they go.
        put((value(Control.streams) * (0.45 + 0.55 * loud)).rounded(), in: .streams)
        put(1.55 * value(Control.reach), in: .reach)
        put(2.1 * value(Control.speed) * (0.7 + 0.6 * loud), in: .speed)
        put(0.55 * value(Control.trail), in: .trail)
        put(value(Control.spread), in: .spread)
        put(travelled, in: .travelled)
        put(flowSpeed, in: .flowSpeed)
        put(turned, in: .turned)
        put(value(Control.sparkSize), in: .sparkSize)
        put(
            Self.sparksTheBrightnessIsSetFor / Float(max(sparkCount, 1)) * value(Control.sparkBrightness),
            in: .sparkLight)
        put((0.3 + 0.9 * sparkle.update(reading, seconds: seconds)) * value(Control.twinkle), in: .twinkle)
        put(value(Control.whiteness), in: .whiteness)
        put(value(Control.heads), in: .heads)
        put(Control.common.shutterSeconds(values: values), in: .shutter)
        put(kicks.numbers[0], in: .kickNumber0)
        put(kicks.numbers[1], in: .kickNumber1)
        put(kicks.numbers[2], in: .kickNumber2)
        put(kicks.numbers[3], in: .kickNumber3)
        uniforms.controls = numbers
    }

    func draw(_ frame: VisualFrame) {
        var uniforms = frame.uniforms
        var count = UInt32(sparkCount)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = frame.picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = Self.background
        pass.colorAttachments[0].storeAction = .store
        guard let render = frame.commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        render.setVertexBytes(&uniforms, length: MemoryLayout<StageUniforms>.stride, index: 1)
        render.setVertexBytes(&count, length: MemoryLayout<UInt32>.size, index: 2)

        render.setRenderPipelineState(drawCore)
        render.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        render.setRenderPipelineState(drawSparks)
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
                visual: Starburst.number, key: key, name: name, group: group, unit: unit, range: range,
                usual: usual, spreadsEvenlyByRatio: byRatio, help: help)
        }

        static let common = CommonControls(visual: Starburst.number)

        static let streams = control(
            "streams", "Streams", "Burst", .count, 12...160, usual: 64, byRatio: true,
            "How many streams each burst has at full loudness. A quieter song fires fewer.")
        static let reach = control(
            "reach", "Reach", "Burst", .times, 0.4...2, usual: 1, byRatio: true,
            "How far the streams fly out.")
        static let speed = control(
            "speed", "Speed", "Burst", .times, 0.3...3, usual: 1, byRatio: true,
            "How fast a burst opens. The louder the song, the faster.")
        static let trail = control(
            "trail", "Trail", "Burst", .times, 0.2...3, usual: 1, byRatio: true,
            "How long a trail of sparks follows each stream's head.")
        static let spread = control(
            "spread", "Spread", "Burst", .times, 0...4, usual: 1,
            "How much each stream's sparks wander off its line.")
        static let flow = control(
            "flow", "Drift between kicks", "Burst", .times, 0...4, usual: 1,
            "How fast the thin field of sparks drifts outward between kicks.")
        static let turning = control(
            "turning", "Turning", "Burst", .times, 0...6, usual: 1,
            "How fast the whole burst turns.")

        static let sparkSize = control(
            "sparkSize", "Size", "Sparks", .times, 0.4...3, usual: 1, byRatio: true,
            "How big each spark is.")
        static let sparkBrightness = control(
            "sparkBrightness", "Brightness", "Sparks", .times, 0.2...4, usual: 1, byRatio: true,
            "How bright the sparks are.")
        static let twinkle = control(
            "twinkle", "Twinkle", "Sparks", .times, 0...2, usual: 1,
            "How much the sparks flicker. The highs in the music add to it.")
        static let whiteness = control(
            "whiteness", "Whiteness", "Sparks", .share, 0...1, usual: 0.5,
            "How pale the sparks are. At 0 each stream is its band's full colour; at 100% they're all white.")
        static let heads = control(
            "heads", "Heads", "Sparks", .times, 0...4, usual: 1,
            "How bright the head leading each stream is.")
        static let blur = control(
            "blur", "Blur", "Sparks", .times, 0...3, usual: 1,
            "How far out of focus the sparks nearest the camera go.")
    }

    static let controls: [VisualControl] = [
        Control.streams, Control.reach, Control.speed, Control.trail, Control.spread, Control.flow,
        Control.turning,
        Control.sparkSize, Control.sparkBrightness, Control.twinkle, Control.whiteness, Control.heads,
        Control.blur, Control.common.streaks,
        Control.common.cameraMovement, Control.common.beatPunch,
        Control.common.glow, Control.common.brightness, Control.common.darkCorners,
    ]

    // MARK: The shaders

    /// Where each number sits among the uniforms' `controls`. The shaders are given the
    /// same names ("star_reach").
    private enum Slot: Int, CaseIterable {
        case streams, reach, speed, trail, spread
        /// How far the drifting field has travelled and how fast it's going, and how
        /// far the burst has turned.
        case travelled, flowSpeed, turned
        case sparkSize, sparkLight, twinkle, whiteness, heads, shutter
        /// How many kicks had landed when each of the last four did, so each burst
        /// points its streams its own way.
        case kickNumber0, kickNumber1, kickNumber2, kickNumber3
    }

    private static let slotsSource = Slot.allCases
        .map { "constant int star_\($0) = \($0.rawValue);" }
        .joined(separator: "\n")

    static let shaderSource = """
        \(slotsSource)

        // The same well-mixed number from 0 to 1 for the same spark and purpose.
        static float starChance(uint spark, uint purpose) {
            uint mixed = spark * 747796405u + purpose * 2891336453u + 1u;
            mixed = ((mixed >> ((mixed >> 28u) + 4u)) ^ mixed) * 277803737u;
            mixed = (mixed >> 22u) ^ mixed;
            return float(mixed) * (1.0 / 4294967296.0);
        }

        // A direction, the same for the same two numbers, spread evenly over a ball.
        static float3 starDirection(uint a, uint b) {
            float up = 1.0 - 2.0 * starChance(a, b);
            float round = 6.2832 * starChance(a, b + 7u);
            float out = sqrt(max(0.0, 1.0 - up * up));
            return float3(out * cos(round), up, out * sin(round));
        }

        // Where a spark is, how bright, and how big, at a moment `earlier` seconds
        // before now. Asked twice for each spark: for now, and for a moment ago (which
        // gives its streak).
        struct StarPlace {
            float3 place;
            float bright;   // 0 if it isn't in the air
            float size;
            int band;
        };

        static StarPlace starPlace(constant StageUniforms &stage, uint id, float earlier) {
            StarPlace star;
            star.bright = 0.0;
            star.size = 1.0;
            star.band = 0;
            star.place = float3(0.0);
            float reach = stage.controls[star_reach];

            if (id % 10u < 9u) {
                // One of a burst's sparks: nine in every ten are.
                uint slot = (id / 10u) % 4u;
                float age = stage.kickAges[slot] - earlier;
                uint streams = uint(max(stage.controls[star_streams], 1.0));
                uint stream = uint(starChance(id, 1u) * 160.0);
                // A quieter song fires fewer of the streams.
                if (stream >= streams || age < 0.0) return star;
                star.band = int(stream % 6u);

                // How far behind the stream's head this spark follows, from 0 (the
                // head itself) to 1 (the last of the trail).
                float behind = starChance(id, 2u);
                bool isHead = behind < 0.012;
                if (isHead) behind = 0.0;
                float since = age - behind * stage.controls[star_trail];
                if (since < 0.0) return star;

                // Out fast and slowing, like anything thrown. A stronger band's
                // streams reach further.
                uint burst = uint(stage.controls[star_kickNumber0 + int(slot)]);
                float3 heading = starDirection(stream, burst * 31u + 3u);
                float farthest = reach * (0.55 + 0.45 * stage.bands[star.band])
                    * mix(0.75, 1.0, starChance(stream, burst + 11u));
                float out = farthest * (1.0 - exp(-since * stage.controls[star_speed]));
                // The trail's sparks wander off the line a little, more the further
                // back they are.
                float3 wander = starDirection(id, 5u) * stage.controls[star_spread]
                    * 0.05 * out * (0.25 + behind);
                star.place = heading * out + wander;

                // The whole burst fades in a couple of seconds.
                float life = age / 2.4;
                float fade = smoothstep(0.0, 0.02, since) * (1.0 - smoothstep(0.45, 1.0, life));
                float along = (1.0 - behind);
                star.bright = fade * (isHead ? 22.0 * stage.controls[star_heads] : 0.6 + 2.0 * along * along);
                star.size = isHead ? 2.6 : mix(0.8, 1.5, starChance(id, 6u));
            } else {
                // One of the thin field that drifts outward between kicks.
                float speed = mix(0.4, 1.0, starChance(id, 8u));
                float gone = stage.controls[star_travelled] - earlier * stage.controls[star_flowSpeed];
                float journey = gone * speed + starChance(id, 9u);
                float part = fract(journey);
                // Each journey heads its own way.
                float3 heading = starDirection(id, uint(floor(journey)) * 13u + 21u);
                star.place = heading * (0.06 + reach * 1.25 * part * part);
                star.band = int(id % 6u);
                star.bright = 1.6 * sin(part * 3.1416);
                star.size = mix(0.6, 1.1, starChance(id, 10u));
            }

            // The whole burst turns slowly.
            float turned = stage.controls[star_turned];
            float2 swung = float2(cos(turned), sin(turned));
            star.place = float3(star.place.x * swung.x + star.place.z * swung.y, star.place.y,
                                star.place.z * swung.x - star.place.x * swung.y);
            return star;
        }

        vertex SparkOut starSpark(constant StageUniforms &stage [[buffer(1)]],
                                  constant uint &count [[buffer(2)]],
                                  uint id [[vertex_id]]) {
            StarPlace star = starPlace(stage, id, 0.0);
            if (star.bright <= 0.0) return noSpark();
            StarPlace before = starPlace(stage, id, stage.controls[star_shutter]);

            // A pale shade of its band's colour.
            float3 colour = mix(bandLightOf(stage, star.band), float3(0.86, 0.84, 1.0),
                                stage.controls[star_whiteness]);
            float twinkle = 1.0 + stage.controls[star_twinkle]
                * sin(stage.time * (3.0 + 9.0 * starChance(id, 12u)) + starChance(id, 13u) * 200.0);
            float bright = star.bright * stage.controls[star_sparkLight] * max(twinkle, 0.15);
            float size = 0.0030 * star.size * stage.controls[star_sparkSize];
            return makeSpark(stage, star.place, before.bright > 0.0 ? before.place : star.place,
                             size, colour * bright);
        }

        struct StarCoreOut {
            float4 position [[position]];
            float2 within;
            half3 light;
        };

        // The glow at the centre, which every stream comes out of. It swells on a kick.
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
            out.light = half3(colour * (0.25 + 0.9 * stage.loudness + 1.6 * stage.beat));
            return out;
        }

        fragment half4 starCoreLight(StarCoreOut in [[stage_in]]) {
            float away = dot(in.within, in.within);
            float shape = exp(-away * 9.0) * 0.5 + exp(-away * 120.0) * 2.5;
            return half4(in.light * half(shape), 1.0h);
        }
        """
}
