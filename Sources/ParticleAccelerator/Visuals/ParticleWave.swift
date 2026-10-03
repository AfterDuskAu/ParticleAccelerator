import Foundation
import Metal
import simd

/// Visualizer 3, Particle Wave (docs/VISUALS.md): a glowing orange-pink line across the
/// middle, with tens of thousands of blue, violet and pink sparks forming peaks above
/// it and a dimmer reflection below.
///
/// With the music:
/// - The peaks are the spectrum, bass on the left and highs on the right.
/// - Sparks ride their peaks with a little drift, then fall back and fade.
/// - The line brightens and flickers with the loudness.
/// - Each kick sends a ripple along the line from the bass end.
final class ParticleWave: Visual {
    static let number = 3

    /// How many pieces the line is drawn in. Enough for a ripple to look smooth.
    private static let lineSegments = 256
    /// The picture is cleared to this before anything is drawn: almost black, with a
    /// little deep blue in it.
    private static let background = MTLClearColor(red: 0.0012, green: 0.0009, blue: 0.0045, alpha: 1)
    /// The sparks' brightness is set for this many. With more, each is dimmer, so a
    /// higher quality gives a finer picture and not a brighter one.
    private static let sparksTheBrightnessIsSetFor: Float = 150_000

    // How the music drives it. These are its built-in settings; the controls editor
    // (phase 8) will let them be changed.
    private var mountains = Mountains()
    private var lineBrightness = LiveSignal(
        SignalChain(source: .loudness, shape: SignalShape(low: 0.25, high: 1, steepness: 1.3, riseSeconds: 0.02, fallSeconds: 0.22)))
    private var sparkle = LiveSignal(
        SignalChain(source: .air, shape: SignalShape(low: 0.2, high: 1, steepness: 1.2, riseSeconds: 0.02, fallSeconds: 0.18)))
    private var punch = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.28)))
    private var drift = CameraDrift()

    /// When each of the last four kicks landed, in stage time.
    private var kickTimes = SIMD4<Float>(repeating: -1_000)
    private var nextKick = 0
    private var beatsSeen = 0

    private let device: MTLDevice
    private let moveSparks: MTLComputePipelineState
    private let drawSparks: MTLRenderPipelineState
    private let drawLine: MTLRenderPipelineState
    private var sparks: MTLBuffer
    private var sparkCount: Int

    init(device: MTLDevice, library: MTLLibrary, particleCount: Int) throws {
        self.device = device
        guard let step = library.makeFunction(name: "waveMoveSparks") else {
            throw StageProblem(message: "A shader is missing: waveMoveSparks.")
        }
        moveSparks = try device.makeComputePipelineState(function: step)
        drawSparks = try device.makeLightPipeline(
            library: library, vertex: "waveSpark", fragment: "waveSparkLight")
        drawLine = try device.makeLightPipeline(
            library: library, vertex: "waveLine", fragment: "waveLineLight")
        sparkCount = particleCount
        sparks = try Self.makeSparks(count: particleCount, device: device)
    }

    func setParticleCount(_ count: Int) throws {
        guard count != sparkCount else { return }
        sparks = try Self.makeSparks(count: count, device: device)
        sparkCount = count
    }

    // MARK: Each frame

    func prepare(_ uniforms: inout StageUniforms, reading: SoundReading) {
        let seconds = Double(uniforms.seconds)

        uniforms.bars = mountains.update(bars: reading.bars, seconds: seconds)
        uniforms.loudness = lineBrightness.update(reading, seconds: seconds)
        uniforms.beat = reading.beat
        uniforms.beatPhase = Float(reading.beatPhase)
        uniforms.bands = SIMD8(
            reading.bands.sub, reading.bands.kick, reading.bands.lowMids, reading.bands.mids,
            reading.bands.vocals, reading.bands.air, 0, 0)

        // Each new beat starts a ripple.
        if reading.beatsHeard != beatsSeen {
            if reading.beatsHeard > beatsSeen {
                kickTimes[nextKick] = uniforms.time
                nextKick = (nextKick + 1) % 4
            }
            beatsSeen = reading.beatsHeard
        }
        uniforms.kickAges = SIMD4(repeating: uniforms.time) - kickTimes

        let camera = drift.camera(
            at: Double(uniforms.time), aspect: uniforms.aspect,
            punchNow: punch.update(reading, seconds: seconds) * reading.loudness)
        uniforms.viewProjection = camera.viewProjection
        uniforms.cameraPosition = SIMD4(camera.position, 0)
        uniforms.tanHalfFieldOfView = tan(camera.fieldOfView / 2)
        uniforms.focusDistance = drift.distance
        // Sparks nearer or further than the line go a little soft.
        uniforms.blurPerUnit = 0.006
        uniforms.fog = 0

        // What the camera sees at the line's distance: half its width and height.
        let halfHeight = uniforms.tanHalfFieldOfView * drift.distance
        let halfWidth = halfHeight * uniforms.aspect
        uniforms.controls = SIMD8(
            halfWidth,  // 0: how far the spectrum reaches to each side
            halfHeight * 0.80,  // 1: how high a full peak reaches
            0.0042,  // 2: half the line's thickness
            sparkle.update(reading, seconds: seconds),  // 3: how much the sparks twinkle
            Self.sparksTheBrightnessIsSetFor / Float(max(sparkCount, 1)),  // 4: each spark's share of the light
            0, 0, 0)
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

        // 2. The line, then the sparks, drawn as light into the picture.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = frame.picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = Self.background
        pass.colorAttachments[0].storeAction = .store
        guard let render = frame.commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        render.setVertexBytes(&uniforms, length: uniformsLength, index: 1)

        // Twice: a wide soft haze, then the bright line itself.
        render.setRenderPipelineState(drawLine)
        render.drawPrimitives(
            type: .triangleStrip, vertexStart: 0, vertexCount: (Self.lineSegments + 1) * 2,
            instanceCount: 2)

        render.setRenderPipelineState(drawSparks)
        render.setVertexBuffer(sparks, offset: 0, index: 0)
        render.drawPrimitives(type: .point, vertexStart: 0, vertexCount: sparkCount)
        render.endEncoding()
    }

    // MARK: The mountains

    /// Turns the spectrum's 64 bars into the mountain range the sparks sit on.
    ///
    /// A song's spectrum is broadly full, and drawn as it stands it's one wide flat
    /// band (seen with a real song, 2026-10-03). The reference picture has separate
    /// peaks all the way across. So:
    /// 1. Each bar is measured against the loudest its own part of the spectrum has
    ///    been lately, so the highs make peaks of their own beside the bass.
    /// 2. The result is on a plain loudness scale, where half as strong is half as
    ///    tall, which makes the strong pitches stand clear of the rest.
    /// 3. Each peak is spread sideways into a triangle, and neighbours join into a
    ///    ridge.
    struct Mountains {
        /// The analyser's bars run from 0 to 1 over this many decibels.
        static let barDecibels: Float = 40
        /// How far to each side a bar's part of the spectrum reaches, in bars.
        static let neighbourhood = 4
        /// A part of the spectrum quieter than this, against the whole song's recent
        /// peak, isn't turned up all the way: faint hiss shouldn't make mountains.
        static let quietestTurnedUp: Float = -24
        /// How fast a part's "loudest lately" falls back, in decibels a second.
        static let forgetting: Float = 5
        /// How far to each side a peak's triangle reaches, in bars.
        static let footprint: Float = 3.5
        /// A peak climbs at once and sinks slowly.
        static let fade = SignalShape(riseSeconds: 0.03, fallSeconds: 0.22)

        /// The loudest each bar has been lately, in decibels below the song's peak.
        private var loudestLately = [Float](repeating: -barDecibels, count: SoundAnalyser.barCount)
        private var heights = [Float](repeating: 0, count: SoundAnalyser.barCount)

        mutating func update(bars: SIMD64<Float>, seconds: Double) -> SIMD64<Float> {
            let count = SoundAnalyser.barCount
            var decibels = [Float](repeating: 0, count: count)
            for bar in 0..<count {
                decibels[bar] = (bars[bar] - 1) * Self.barDecibels
                loudestLately[bar] = max(decibels[bar], loudestLately[bar] - Self.forgetting * Float(seconds))
            }

            for bar in 0..<count {
                // Steps 1 and 2.
                var loudestNearby = Self.quietestTurnedUp
                for near in max(0, bar - Self.neighbourhood)...min(count - 1, bar + Self.neighbourhood) {
                    loudestNearby = max(loudestNearby, loudestLately[near])
                }
                var height = pow(10, (decibels[bar] - loudestNearby) / 20)
                // A bar at the very bottom of the analyser's range is silence.
                height *= min(1, bars[bar] / 0.1)
                heights[bar] = Self.fade.fade(heights[bar], towards: min(1, height), seconds: seconds)
            }

            // Step 3.
            var range = SIMD64<Float>(repeating: 0)
            let reach = Int(Self.footprint.rounded(.up))
            for bar in 0..<count {
                var tallest: Float = 0
                for near in max(0, bar - reach)...min(count - 1, bar + reach) {
                    let slope = max(0, 1 - Float(abs(near - bar)) / Self.footprint)
                    tallest = max(tallest, heights[near] * slope)
                }
                range[bar] = tallest
            }
            return range
        }
    }

    // MARK: The sparks

    /// One spark, as the graphics card keeps it: 32 bytes.
    struct Spark {
        /// x, y, z, and its age from 0 (born) to 1 (gone).
        var position: SIMD4<Float>
        /// x: its sideways drift. y: how many lives it has had. z: spare.
        /// w: its own unchanging number from 0 to 1, which everything else about it
        /// (size, colour, how high it rides) is worked out from.
        var nature: SIMD4<Float>
    }

    /// Where the sparks start. The same every time, so tests see the same picture.
    static func startingSparks(count: Int) -> [Spark] {
        (0..<count).map { index in
            // Multiples of these numbers never line up, so the sparks are spread evenly.
            let own = Double(index) + 0.5
            let number = Float((own * 0.618_033_988_749_895).truncatingRemainder(dividingBy: 1))
            let age = Float((own * 0.754_877_666_246_693).truncatingRemainder(dividingBy: 1))
            let along = Float((own * 0.569_840_290_998_053).truncatingRemainder(dividingBy: 1))
            return Spark(
                position: SIMD4((along * 2 - 1) * 1.9, 0, 0, age),
                nature: SIMD4(0, 0, 0, number))
        }
    }

    /// Puts the starting sparks in memory only the graphics card uses.
    private static func makeSparks(count: Int, device: MTLDevice) throws -> MTLBuffer {
        let starting = startingSparks(count: count)
        let length = count * MemoryLayout<Spark>.stride
        guard length > 0,
            let filled = device.makeBuffer(bytes: starting, length: length, options: .storageModeShared),
            let sparks = device.makeBuffer(length: length, options: .storageModePrivate),
            let queue = device.makeCommandQueue(), let commands = queue.makeCommandBuffer(),
            let copy = commands.makeBlitCommandEncoder()
        else {
            throw StageProblem(
                message: "The graphics card couldn't make room for \(count.formatted()) sparks. Try a lower quality.")
        }
        copy.copy(from: filled, sourceOffset: 0, to: sparks, destinationOffset: 0, size: length)
        copy.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return sparks
    }

    // MARK: The shaders

    static let shaderSource = """
        struct WaveSpark {
            float4 position;   // x, y, z, and age from 0 (born) to 1 (gone)
            float4 nature;     // sideways drift, lives so far, spare, its own number
        };

        // What kind of spark this is, from its own number.
        static bool waveIsReflection(float own) { return chance(own * 13.37) < 0.34; }
        static bool waveIsStray(float own) { return chance(own * 13.37) > 0.945; }

        // Moves every spark on by one frame.
        kernel void waveMoveSparks(device WaveSpark *sparks [[buffer(0)]],
                                   constant StageUniforms &stage [[buffer(1)]],
                                   constant uint &count [[buffer(2)]],
                                   uint index [[thread_position_in_grid]]) {
            if (index >= count) return;
            WaveSpark spark = sparks[index];
            float own = spark.nature.w;
            float lives = spark.nature.y;
            float halfWidth = stage.controls[0];
            float reach = stage.controls[1];

            // Sparks live from two and a half to six seconds.
            float lifetime = mix(2.5, 6.0, chance(own * 91.7));
            float age = spark.position.w + stage.seconds / lifetime;
            if (age >= 1.0) {
                // Gone, and born again somewhere new along the line.
                age = fract(age);
                lives += 1.0;
                float place = chance2(own, lives) * 2.0 - 1.0;
                spark.position.x = place * halfWidth * 1.12;
                spark.position.y = 0.0;
                spark.position.z = (chance2(own * 3.1, lives) - 0.5) * 0.55;
                spark.nature.x = (chance2(own * 7.7, lives) - 0.5) * 0.07;
            }

            // How high the music's peak is where this spark is.
            float along = spark.position.x / halfWidth * 0.5 + 0.5;
            float peak = spectrumAt(stage, along);

            // Most sparks sit low on their peak, and fewer near its top.
            float share = pow(chance(own * 57.3 + 0.5), 1.9);
            float target = share * (peak * reach + 0.03);
            if (waveIsStray(own)) {
                // A few float well clear of the peaks.
                target = (0.2 + share * 1.5) * (0.10 + peak * 0.55) * reach * 1.6;
            }
            // Near the end of its life a spark lets go and falls back.
            target *= 1.0 - smoothstep(0.70, 1.0, age);
            if (waveIsReflection(own)) target *= -0.85;

            // Quick to climb, slow to fall.
            float height = spark.position.y;
            float pull = fabs(target) > fabs(height) ? 10.0 : 2.3;
            height += (target - height) * (1.0 - exp(-pull * stage.seconds));

            // A little drift of its own, more where the music is strong.
            float sway = sin(stage.time * (0.6 + 1.7 * chance(own * 3.3)) + own * 60.0);
            float bob = cos(stage.time * (0.8 + 1.3 * chance(own * 5.1)) + own * 40.0);
            spark.position.x += (spark.nature.x + 0.03 * sway * (0.3 + peak)) * stage.seconds;
            height += 0.02 * bob * (0.4 + 2.0 * peak) * stage.seconds;

            spark.position.y = height;
            spark.position.w = age;
            spark.nature.y = lives;
            sparks[index] = spark;
        }

        struct WaveSparkOut {
            float4 position [[position]];
            float size [[point_size]];
            half3 light;
        };

        vertex WaveSparkOut waveSpark(const device WaveSpark *sparks [[buffer(0)]],
                                      constant StageUniforms &stage [[buffer(1)]],
                                      uint id [[vertex_id]]) {
            WaveSpark spark = sparks[id];
            float own = spark.nature.w;
            float age = spark.position.w;
            float reach = max(stage.controls[1], 0.001);
            float twinkling = stage.controls[3];

            WaveSparkOut out;
            out.position = stage.viewProjection * float4(spark.position.xyz, 1.0);
            float distance = max(out.position.w, 0.05);

            // Its size on the stage, then in pixels at its distance. Most are tiny, and
            // a few are big and soft.
            bool big = chance(own * 23.9) > 0.988;
            float tiny = chance(own * 31.1);
            float stageSize = mix(0.0016, 0.0042, tiny * tiny) + (big ? 0.009 : 0.0);
            float pixels = stageSize / (distance * stage.tanHalfFieldOfView) * stage.pictureSize.y;
            // Out of focus: bigger and fainter.
            float blur = fabs(distance - stage.focusDistance) * stage.blurPerUnit * stage.pictureSize.y;
            float shown = max(pixels + blur, 1.6);
            out.size = shown;
            float spread = (pixels * pixels) / (shown * shown);

            // Pink by the line, violet higher, blue at the top.
            float3 pink = float3(1.00, 0.10, 0.52);
            float3 violet = float3(0.52, 0.13, 1.00);
            float3 blue = float3(0.09, 0.24, 1.00);
            float high = saturate(fabs(spark.position.y) / reach);
            float3 colour = mix(pink, violet, smoothstep(0.05, 0.45, high));
            colour = mix(colour, blue, smoothstep(0.40, 0.95, high));
            // Each leans a little its own way, and the big ones are light blue.
            colour = mix(colour, blue, 0.4 * chance(own * 71.3));
            if (big) colour = float3(0.22, 0.50, 1.00);

            float fade = smoothstep(0.0, 0.10, age) * (1.0 - smoothstep(0.72, 1.0, age));
            float twinkle = 1.0 + (0.35 + 0.9 * twinkling)
                * sin(stage.time * (2.5 + 9.0 * chance(own * 17.3)) + own * 200.0);
            // Most sparks are faint and make a mist together. One in eight is bright
            // enough to be seen as a spark of its own.
            bool bright1in8 = chance(own * 47.9) > 0.875;
            float bright = (bright1in8 ? 4.4 : 0.6) * stage.controls[4];
            bright *= fade * max(twinkle, 0.15) * max(spread, 0.12);
            // Sparks lying on the line itself are dimmed, so that in a quiet passage
            // they don't pile up into a thick bright bar.
            bright *= mix(0.3, 1.0, smoothstep(0.0, 0.07, high));
            if (big) bright *= 0.35;
            if (waveIsStray(own)) bright *= 0.8;
            if (waveIsReflection(own)) {
                colour = mix(colour, blue, 0.45);
                bright *= 0.45;
            }
            out.light = half3(colour * bright);
            return out;
        }

        // A soft round spark, brightest in the middle.
        fragment half4 waveSparkLight(WaveSparkOut in [[stage_in]], float2 spot [[point_coord]]) {
            float edge = saturate(1.0 - length(spot - 0.5) * 2.0);
            return half4(in.light * half(edge * edge), 1.0h);
        }

        struct WaveLineOut {
            float4 position [[position]];
            float across;   // -1 at one edge of the line, 0 in the middle, 1 at the other
            half3 light;
        };

        // The line across the middle. Drawn twice: first as a wide soft haze, then as
        // the bright line itself.
        vertex WaveLineOut waveLine(constant StageUniforms &stage [[buffer(1)]],
                                    uint id [[vertex_id]], uint pass [[instance_id]]) {
            const float segments = \(lineSegments).0;
            float along = float(id / 2) / segments;
            float side = (id % 2 == 0) ? -1.0 : 1.0;
            float halfWidth = stage.controls[0];
            float x = (along * 2.0 - 1.0) * halfWidth * 1.25;
            // Where this is on the spectrum (the line runs a little past each end).
            float onSpectrum = x / halfWidth * 0.5 + 0.5;

            // Each kick sends a bump along the line from the bass end, fading as it goes.
            float height = 0.0;
            for (int kick = 0; kick < 4; kick++) {
                float since = stage.kickAges[kick];
                float front = since * 1.6 - 0.05;
                float from = onSpectrum - front;
                height += 0.045 * exp(-from * from / 0.004) * exp(-since * 2.2);
            }
            // And it trembles a little under the peaks.
            float peak = spectrumAt(stage, onSpectrum);
            height += 0.006 * peak * sin(x * 90.0 + stage.time * 14.0);

            bool haze = pass == 0;
            float thickness = stage.controls[2] * (haze ? 22.0 : 1.0);
            WaveLineOut out;
            out.position = stage.viewProjection * float4(x, height + side * thickness, 0.0, 1.0);
            out.across = side;

            // Orange-pink, brighter and flickering with the loudness.
            float flicker = 0.85 + 0.15 * sin(stage.time * 31.0 + x * 7.0) * sin(stage.time * 17.3);
            float bright = (0.55 + 6.0 * stage.loudness) * flicker * (1.0 + 0.6 * peak);
            float3 colour = haze ? float3(1.00, 0.16, 0.50) * 0.035 : float3(1.00, 0.40, 0.16);
            out.light = half3(colour * bright);
            return out;
        }

        // Brightest along its middle, fading to nothing at its edges.
        fragment half4 waveLineLight(WaveLineOut in [[stage_in]]) {
            float falloff = exp(-in.across * in.across * 4.5);
            return half4(in.light * half(falloff), 1.0h);
        }
        """
}
