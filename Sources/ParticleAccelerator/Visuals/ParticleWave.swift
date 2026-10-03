import Foundation
import Metal
import simd

/// Visualizer 3, Particle Wave (docs/VISUALS.md): a glowing line across the middle, with
/// tens of thousands of sparks forming peaks above it and a dimmer reflection below.
///
/// With the music:
/// - The peaks are the spectrum, bass on the left and highs on the right.
/// - Each of the six bands has a section of its own, in the band's own colour: its
///   sparks, its reflection and its piece of the line.
/// - Sparks leap up their peaks on a hit and drop straight back, so one beat is over
///   before the next lands.
/// - Each section of the line brightens with its own band.
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

    // How the music drives it. These are its own settings; a person changes them in the
    // controls panel (see "The controls" below).
    private var mountains = Mountains()
    /// How brightly each band's section of the line glows.
    private var bandGlow = Band.allCases.map { band in
        LiveSignal(
            SignalChain(
                source: band.source,
                shape: SignalShape(low: 0.15, high: 1, steepness: 1.3, riseSeconds: 0.02, fallSeconds: 0.15)))
    }
    private var sparkle = LiveSignal(
        SignalChain(source: .air, shape: SignalShape(low: 0.2, high: 1, steepness: 1.2, riseSeconds: 0.02, fallSeconds: 0.18)))
    private var punch = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.28)))
    /// How the camera moves before the person's own "Camera movement" and "Beat punch".
    private let usualDrift = CameraDrift()

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

    func prepare(
        _ uniforms: inout StageUniforms, finishing: inout FinishUniforms, reading: SoundReading,
        values: ControlValues
    ) {
        let seconds = Double(uniforms.seconds)
        func value(_ control: VisualControl) -> Float { values.value(of: control) }

        mountains.footprint = value(Control.peakWidth)
        mountains.decibelsToHalve = value(Control.quietPitches)
        mountains.heldShare = value(Control.heldSound)
        mountains.fallSeconds = Double(value(Control.fall))
        uniforms.bars = mountains.update(bars: reading.bars, seconds: seconds)
        uniforms.beat = reading.beat
        uniforms.beatPhase = Float(reading.beatPhase)
        for band in Band.allCases {
            uniforms.bands[band.rawValue] = bandGlow[band.rawValue].update(reading, seconds: seconds)
        }
        uniforms.setBandLight(from: values)

        // Each new beat starts a ripple.
        if reading.beatsHeard != beatsSeen {
            if reading.beatsHeard > beatsSeen {
                kickTimes[nextKick] = uniforms.time
                nextKick = (nextKick + 1) % 4
            }
            beatsSeen = reading.beatsHeard
        }
        uniforms.kickAges = SIMD4(repeating: uniforms.time) - kickTimes

        var drift = usualDrift
        let movement = value(Control.cameraMovement)
        drift.sideways *= movement
        drift.upAndDown *= movement
        drift.roll *= movement
        drift.breath *= movement
        drift.punch *= value(Control.beatPunch)
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

        finishing.glow = value(Control.glow)
        finishing.exposure = value(Control.brightness)
        finishing.vignette = value(Control.darkCorners)

        // What the camera sees at the line's distance: half its width and height.
        let halfHeight = uniforms.tanHalfFieldOfView * drift.distance
        let halfWidth = halfHeight * uniforms.aspect
        var numbers = SIMD32<Float>(repeating: 0)
        func put(_ number: Float, in slot: Slot) { numbers[slot.rawValue] = number }
        put(halfWidth, in: .halfWidth)
        put(halfHeight * value(Control.peakHeight), in: .reach)
        put(0.0042 * value(Control.lineThickness), in: .lineThickness)
        put(sparkle.update(reading, seconds: seconds), in: .sparkle)
        put(
            Self.sparksTheBrightnessIsSetFor / Float(max(sparkCount, 1)) * value(Control.sparkBrightness),
            in: .sparkLight)
        put(1 / value(Control.rise), in: .riseRate)
        put(1 / value(Control.fall), in: .fallRate)
        put(value(Control.drift), in: .drift)
        put(value(Control.sparkSize), in: .sparkSize)
        put(value(Control.twinkle), in: .twinkle)
        // Most sparks sit low on their peak. The fuller the peaks are asked to be, the
        // more of them sit near the top.
        put(1.5 / value(Control.fullness), in: .topThinness)
        put(value(Control.floating), in: .floating)
        put(value(Control.reflection), in: .reflection)
        put(value(Control.lineBrightness), in: .lineLight)
        put(value(Control.lineGlow), in: .lineGlow)
        put(value(Control.ripple), in: .ripple)
        put(value(Control.tremble), in: .tremble)
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

    // MARK: The controls

    /// What a person can change about this visual, with its own setting for each. The
    /// controls panel shows them in this order, under these headings.
    enum Control {
        private static func control(
            _ key: String, _ name: String, _ group: String, _ unit: VisualControl.Unit,
            _ range: ClosedRange<Float>, usual: Float, byRatio: Bool = false, _ help: String
        ) -> VisualControl {
            VisualControl(
                visual: ParticleWave.number, key: key, name: name, group: group, unit: unit, range: range,
                usual: usual, spreadsEvenlyByRatio: byRatio, help: help)
        }

        static let peakHeight = control(
            "peakHeight", "Height", "Peaks", .share, 0.2...1, usual: 0.88,
            "How high a full peak reaches, as a share of the space above the line.")
        static let peakWidth = control(
            "peakWidth", "Width", "Peaks", .bars, 1...8, usual: 2.5,
            "How wide each peak is. Narrow peaks stand apart; wide ones join into ridges.")
        static let quietPitches = control(
            "quietPitches", "Quieter pitches", "Peaks", .decibels, 2...14, usual: 5,
            "A pitch this much quieter than the loudest nearby stands half as tall. Higher shows more of the quieter pitches; lower leaves only the strongest.")
        static let heldSound = control(
            "heldSound", "Held sound", "Peaks", .share, 0.1...1, usual: 0.55,
            "How tall a sound that holds steady stands. Lower makes each fresh hit stand out more.")

        static let rise = control(
            "rise", "Rise", "Movement", .seconds, 0.015...0.4, usual: 0.035, byRatio: true,
            "How long sparks take to leap up a peak. Lower is snappier; higher is smoother.")
        static let fall = control(
            "fall", "Fall", "Movement", .seconds, 0.03...1.5, usual: 0.11, byRatio: true,
            "How long sparks take to drop back to the line. Lower keeps one beat clear of the next; higher lets them hang.")
        static let drift = control(
            "drift", "Drift", "Movement", .times, 0...4, usual: 1,
            "How much the sparks wander and bob on their own.")
        static let cameraMovement = control(
            "cameraMovement", "Camera movement", "Movement", .times, 0...4, usual: 1,
            "How far the camera drifts, rolls and breathes. At 0 it stands still.")
        static let beatPunch = control(
            "beatPunch", "Beat punch", "Movement", .times, 0...5, usual: 1,
            "How far the camera jumps towards the stage on each beat.")

        static let sparkSize = control(
            "sparkSize", "Size", "Sparks", .times, 0.4...3, usual: 1, byRatio: true,
            "How big each spark is.")
        static let sparkBrightness = control(
            "sparkBrightness", "Brightness", "Sparks", .times, 0.2...4, usual: 1, byRatio: true,
            "How bright the sparks are.")
        static let twinkle = control(
            "twinkle", "Twinkle", "Sparks", .times, 0...2, usual: 1,
            "How much the sparks flicker. The highs in the music add to it.")
        static let fullness = control(
            "fullness", "Fullness", "Sparks", .times, 0.4...2.5, usual: 1, byRatio: true,
            "How many of a peak's sparks sit near its top. Lower leaves the tops thin; higher fills the peaks.")
        static let floating = control(
            "floating", "Floating sparks", "Sparks", .share, 0...0.25, usual: 0.03,
            "The share of sparks that float clear of the peaks.")
        static let reflection = control(
            "reflection", "Reflection", "Sparks", .share, 0...1, usual: 0.45,
            "How bright the reflection below the line is, against the peaks above it.")

        static let lineThickness = control(
            "lineThickness", "Thickness", "Line", .times, 0.3...6, usual: 1, byRatio: true,
            "How thick the line is.")
        static let lineBrightness = control(
            "lineBrightness", "Brightness", "Line", .times, 0...4, usual: 1,
            "How bright the line is. Each section still brightens with its own band.")
        static let lineGlow = control(
            "lineGlow", "Haze", "Line", .times, 0...5, usual: 1,
            "How strong the soft haze around the line is.")
        static let ripple = control(
            "ripple", "Kick ripple", "Line", .times, 0...5, usual: 1,
            "How tall the bump is that each kick sends along the line.")
        static let tremble = control(
            "tremble", "Tremble", "Line", .times, 0...5, usual: 1,
            "How much the line shivers under the peaks.")

        static let glow = control(
            "glow", "Glow", "Picture", .times, 0...2.5, usual: 0.7,
            "How much everything bright glows.")
        static let brightness = control(
            "brightness", "Brightness", "Picture", .times, 0.3...3, usual: 1, byRatio: true,
            "How bright the whole picture is.")
        static let darkCorners = control(
            "darkCorners", "Dark corners", "Picture", .share, 0...1, usual: 0.5,
            "How much the picture darkens towards its corners.")
    }

    static let controls: [VisualControl] = [
        Control.peakHeight, Control.peakWidth, Control.quietPitches, Control.heldSound,
        Control.rise, Control.fall, Control.drift, Control.cameraMovement, Control.beatPunch,
        Control.sparkSize, Control.sparkBrightness, Control.twinkle, Control.fullness, Control.floating,
        Control.reflection,
        Control.lineThickness, Control.lineBrightness, Control.lineGlow, Control.ripple, Control.tremble,
        Control.glow, Control.brightness, Control.darkCorners,
    ]

    // MARK: The mountains

    /// Turns the spectrum's 64 bars into the mountain range the sparks sit on.
    ///
    /// A song's spectrum is broadly full, and drawn as it stands it's one wide flat
    /// band (seen with a real song, 2026-10-03). The reference picture has separate
    /// peaks all the way across. So:
    /// 1. Each bar is measured against the loudest its own part of the spectrum has
    ///    been lately, so the highs make peaks of their own beside the bass.
    /// 2. The strong pitches are made to stand well clear of the rest.
    /// 3. A sound that holds steady sinks to part of its height, and only one that has
    ///    just jumped up stands at its full height. In a busy passage everything is
    ///    loud all the time, and without this the beats can't be seen in it (the
    ///    owner, 2026-10-03: "everything is just mushed together").
    /// 4. A peak climbs at once and drops back quickly, so that one beat is over before
    ///    the next lands.
    /// 5. Each peak is spread sideways into a triangle, and neighbours join into a
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
        /// A pitch this many decibels quieter than the loudest nearby stands half as
        /// tall.
        var decibelsToHalve = Control.quietPitches.usual
        /// A sound that holds steady stands at this share of its height.
        var heldShare = Control.heldSound.usual
        /// A jump of this many decibels above where a bar has been sitting is a full
        /// hit.
        static let fullJump: Float = 8
        /// "Where a bar has been sitting" follows the sound up slowly, so a hit stands
        /// clear of it for a moment, and down quickly, so it's ready for the next hit.
        static let settling = SignalShape(riseSeconds: 0.30, fallSeconds: 0.10)
        /// How far to each side a peak's triangle reaches, in bars.
        var footprint = Control.peakWidth.usual
        /// A peak is up within a frame or two, and takes this long to sink.
        static let riseSeconds = 0.012
        var fallSeconds = Double(Control.fall.usual)

        /// The loudest each bar has been lately, in decibels below the song's peak.
        private var loudestLately = [Float](repeating: -barDecibels, count: SoundAnalyser.barCount)
        /// Where each bar has been sitting, in the same decibels.
        private var sittingAt = [Float](repeating: -barDecibels, count: SoundAnalyser.barCount)
        private var heights = [Float](repeating: 0, count: SoundAnalyser.barCount)

        mutating func update(bars: SIMD64<Float>, seconds: Double) -> SIMD64<Float> {
            let count = SoundAnalyser.barCount
            var decibels = [Float](repeating: 0, count: count)
            for bar in 0..<count {
                decibels[bar] = (bars[bar] - 1) * Self.barDecibels
                loudestLately[bar] = max(decibels[bar], loudestLately[bar] - Self.forgetting * Float(seconds))
            }

            let fade = SignalShape(riseSeconds: Self.riseSeconds, fallSeconds: fallSeconds)
            for bar in 0..<count {
                // Steps 1 and 2.
                var loudestNearby = Self.quietestTurnedUp
                for near in max(0, bar - Self.neighbourhood)...min(count - 1, bar + Self.neighbourhood) {
                    loudestNearby = max(loudestNearby, loudestLately[near])
                }
                var height = pow(0.5, (loudestNearby - decibels[bar]) / decibelsToHalve)
                // A bar at the very bottom of the analyser's range is silence.
                height *= min(1, bars[bar] / 0.1)

                // Step 3.
                let jump = min(1, max(0, decibels[bar] - sittingAt[bar]) / Self.fullJump)
                height *= heldShare + (1 - heldShare) * jump
                sittingAt[bar] = Self.settling.fade(sittingAt[bar], towards: decibels[bar], seconds: seconds)

                // Step 4.
                heights[bar] = fade.fade(heights[bar], towards: min(1, height), seconds: seconds)
            }

            // Step 5.
            var range = SIMD64<Float>(repeating: 0)
            let reach = Int(footprint.rounded(.up))
            for bar in 0..<count {
                var tallest: Float = 0
                for near in max(0, bar - reach)...min(count - 1, bar + reach) {
                    let slope = max(0, 1 - Float(abs(near - bar)) / footprint)
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

    /// Where each band ends along the spectrum, for the shaders. Written out from
    /// `Band`, so the sections here and the sound check's bars can't drift apart.
    static let bandsSource: String = {
        // The shaders count along the spectrum from 0 at the middle of the first bar to
        // 1 at the middle of the last.
        let ends = Band.allCases.dropFirst().map { band -> String in
            let place = Band.barPlace(ofHz: band.frequencies.lowerBound)
            return "\((place - 0.5) / Float(SoundAnalyser.barCount - 1))"
        }
        return "constant float waveBandEnds[\(ends.count)] = { \(ends.joined(separator: ", ")) };"
    }()

    /// Where each number sits among the uniforms' `controls`. The shaders are given the
    /// same names ("wave_reach"), so Swift and Metal can't disagree.
    private enum Slot: Int, CaseIterable {
        /// How far the spectrum reaches to each side, and how high a full peak reaches.
        case halfWidth, reach
        /// Half the line's thickness.
        case lineThickness
        /// How much the sparks twinkle right now, from the highs.
        case sparkle
        /// Each spark's share of the light.
        case sparkLight
        /// How fast sparks climb and drop, as "so much of the way each second".
        case riseRate, fallRate
        case drift, sparkSize, twinkle, topThinness, floating, reflection
        case lineLight, lineGlow, ripple, tremble
    }

    private static let slotsSource = Slot.allCases
        .map { "constant int wave_\($0) = \($0.rawValue);" }
        .joined(separator: "\n")

    static let shaderSource = """
        struct WaveSpark {
            float4 position;   // x, y, z, and age from 0 (born) to 1 (gone)
            float4 nature;     // sideways drift, lives so far, spare, its own number
        };

        \(bandsSource)
        \(slotsSource)

        // Which band a place along the spectrum is in, as a number from 0 (sub) to 5
        // (air). It slides from one whole number to the next across each border, so
        // the colours meet softly.
        static float waveBandAt(float along) {
            float band = 0.0;
            for (int border = 0; border < 5; border++) {
                band += smoothstep(-0.018, 0.018, along - waveBandEnds[border]);
            }
            return band;
        }

        // The colour of the band at a place along the spectrum.
        static float3 waveColourAt(constant StageUniforms &stage, float along) {
            float band = waveBandAt(along);
            int lower = min(int(band), 4);
            return mix(bandLightOf(stage, lower), bandLightOf(stage, lower + 1), band - float(lower));
        }

        // How loud the band at a place along the spectrum is, from 0 to 1.
        static float waveBandLevelAt(constant StageUniforms &stage, float along) {
            float band = waveBandAt(along);
            int lower = min(int(band), 4);
            return mix(stage.bands[lower], stage.bands[lower + 1], band - float(lower));
        }

        // What kind of spark this is, from its own number.
        static bool waveIsReflection(float own) { return chance(own * 13.37) < 0.34; }
        static bool waveIsStray(constant StageUniforms &stage, float own) {
            return chance(own * 13.37) > 1.0 - stage.controls[wave_floating];
        }

        // Moves every spark on by one frame.
        kernel void waveMoveSparks(device WaveSpark *sparks [[buffer(0)]],
                                   constant StageUniforms &stage [[buffer(1)]],
                                   constant uint &count [[buffer(2)]],
                                   uint index [[thread_position_in_grid]]) {
            if (index >= count) return;
            WaveSpark spark = sparks[index];
            float own = spark.nature.w;
            float lives = spark.nature.y;
            float halfWidth = stage.controls[wave_halfWidth];
            float reach = stage.controls[wave_reach];
            float drifting = stage.controls[wave_drift];

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
            float share = pow(chance(own * 57.3 + 0.5), stage.controls[wave_topThinness]);
            float target = share * (peak * reach + 0.03);
            if (waveIsStray(stage, own)) {
                // A few float clear of the peaks.
                target = (0.2 + share * 1.5) * (0.06 + peak * 0.55) * reach * 1.3;
            }
            // Near the end of its life a spark lets go and falls back.
            target *= 1.0 - smoothstep(0.70, 1.0, age);
            if (waveIsReflection(own)) target *= -0.85;

            // It leaps up, since a drum hit is over in a twentieth of a second, and
            // drops back quickly: a spark still in the air when the next beat lands
            // blurs the two beats into one.
            float height = spark.position.y;
            float pull = fabs(target) > fabs(height)
                ? stage.controls[wave_riseRate] : stage.controls[wave_fallRate];
            height += (target - height) * (1.0 - exp(-pull * stage.seconds));

            // A little drift of its own, more where the music is strong.
            float sway = sin(stage.time * (0.6 + 1.7 * chance(own * 3.3)) + own * 60.0);
            float bob = cos(stage.time * (0.8 + 1.3 * chance(own * 5.1)) + own * 40.0);
            spark.position.x += (spark.nature.x + 0.03 * sway * (0.3 + peak)) * drifting * stage.seconds;
            height += 0.02 * bob * (0.4 + 2.0 * peak) * drifting * stage.seconds;

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
            float reach = max(stage.controls[wave_reach], 0.001);
            float twinkling = stage.controls[wave_sparkle];

            WaveSparkOut out;
            out.position = stage.viewProjection * float4(spark.position.xyz, 1.0);
            float distance = max(out.position.w, 0.05);

            // Its size on the stage, then in pixels at its distance. Most are tiny, and
            // a few are big and soft.
            bool big = chance(own * 23.9) > 0.988;
            float tiny = chance(own * 31.1);
            float stageSize = mix(0.0016, 0.0042, tiny * tiny) + (big ? 0.009 : 0.0);
            stageSize *= stage.controls[wave_sparkSize];
            float pixels = stageSize / (distance * stage.tanHalfFieldOfView) * stage.pictureSize.y;
            // Out of focus: bigger and fainter.
            float blur = fabs(distance - stage.focusDistance) * stage.blurPerUnit * stage.pictureSize.y;
            float shown = max(pixels + blur, 1.6);
            out.size = shown;
            float spread = (pixels * pixels) / (shown * shown);

            // The colour of the band it's in. Each is a little paler or deeper than
            // its neighbours, and the big ones are pale.
            float along = spark.position.x / max(stage.controls[wave_halfWidth], 0.001) * 0.5 + 0.5;
            float3 colour = waveColourAt(stage, along);
            colour = mix(colour, float3(1.0), 0.22 * chance(own * 71.3));
            if (big) colour = mix(colour, float3(1.0), 0.4);
            float high = saturate(fabs(spark.position.y) / reach);

            float fade = smoothstep(0.0, 0.10, age) * (1.0 - smoothstep(0.72, 1.0, age));
            float twinkle = 1.0 + (0.35 + 0.9 * twinkling) * stage.controls[wave_twinkle]
                * sin(stage.time * (2.5 + 9.0 * chance(own * 17.3)) + own * 200.0);
            // Most sparks are faint and make a mist together. One in eight is bright
            // enough to be seen as a spark of its own.
            bool bright1in8 = chance(own * 47.9) > 0.875;
            float bright = (bright1in8 ? 4.4 : 0.6) * stage.controls[wave_sparkLight];
            bright *= fade * max(twinkle, 0.15) * max(spread, 0.12);
            // Sparks lying on the line itself are dimmed, so that in a quiet passage
            // they don't pile up into a thick bright bar.
            bright *= mix(0.3, 1.0, smoothstep(0.0, 0.07, high));
            if (big) bright *= 0.35;
            if (waveIsStray(stage, own)) bright *= 0.8;
            if (waveIsReflection(own)) bright *= stage.controls[wave_reflection];
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
            float halfWidth = stage.controls[wave_halfWidth];
            float x = (along * 2.0 - 1.0) * halfWidth * 1.25;
            // Where this is on the spectrum (the line runs a little past each end).
            float onSpectrum = x / halfWidth * 0.5 + 0.5;

            // Each kick sends a bump along the line from the bass end, fading as it goes.
            float height = 0.0;
            for (int kick = 0; kick < 4; kick++) {
                float since = stage.kickAges[kick];
                float front = since * 1.6 - 0.05;
                float from = onSpectrum - front;
                height += 0.045 * stage.controls[wave_ripple] * exp(-from * from / 0.004) * exp(-since * 2.2);
            }
            // And it trembles a little under the peaks.
            float peak = spectrumAt(stage, onSpectrum);
            height += 0.006 * stage.controls[wave_tremble] * peak * sin(x * 90.0 + stage.time * 14.0);

            bool haze = pass == 0;
            float thickness = stage.controls[wave_lineThickness] * (haze ? 22.0 : 1.0);
            WaveLineOut out;
            out.position = stage.viewProjection * float4(x, height + side * thickness, 0.0, 1.0);
            out.across = side;

            // Its band's colour, brighter and flickering as that band gets louder.
            float flicker = 0.85 + 0.15 * sin(stage.time * 31.0 + x * 7.0) * sin(stage.time * 17.3);
            float level = waveBandLevelAt(stage, onSpectrum);
            float bright = (0.55 + 6.0 * level) * flicker * (1.0 + 0.6 * peak) * stage.controls[wave_lineLight];
            float3 colour = waveColourAt(stage, onSpectrum) * (haze ? 0.05 * stage.controls[wave_lineGlow] : 1.0);
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
