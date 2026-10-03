import Foundation
import Metal
import Testing
import simd

@testable import ParticleAccelerator

// MARK: Shaders

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func everyShaderCompiles() throws {
    let device = try #require(graphicsCard)
    #expect(!StageRenderer.allShaderSources.isEmpty)
    for (name, source) in StageRenderer.allShaderSources {
        let library = try StageRenderer.compile(source, named: name, device: device)
        // The stage's own shaders are in every one.
        for function in ["wholeScreen", "glowDown", "glowUp", "finish"] {
            #expect(library.makeFunction(name: function) != nil, "\(name) is missing \(function)")
        }
    }
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func swiftAndMetalAgreeOnWhereTheUniformsAre() throws {
    // Ask Metal where it put each member of StageUniforms, and compare with Swift.
    let device = try #require(graphicsCard)
    let probe = """
        kernel void probe(device float *out [[buffer(0)]], constant StageUniforms &stage [[buffer(1)]],
                          uint index [[thread_position_in_grid]]) {
            out[index] = stage.bars[index % 64] + stage.controls[0] + stage.kickAges[0] + stage.bands[0]
                + stage.viewProjection[0][0] + stage.cameraPosition.x + stage.pictureSize.x + stage.aspect
                + stage.tanHalfFieldOfView + stage.time + stage.seconds + stage.loudness + stage.beat
                + stage.beatPhase + stage.focusDistance + stage.blurPerUnit + stage.fog;
        }
        """
    let library = try device.makeLibrary(source: StageShaders.common + probe, options: nil)
    var reflection: MTLComputePipelineReflection?
    _ = try device.makeComputePipelineState(
        function: try #require(library.makeFunction(name: "probe")),
        options: [.bindingInfo, .bufferTypeInfo], reflection: &reflection)
    let binding = try #require(
        reflection?.bindings.compactMap { $0 as? MTLBufferBinding }.first { $0.name == "stage" })
    let members = try #require(binding.bufferStructType?.members)

    #expect(binding.bufferDataSize == MemoryLayout<StageUniforms>.stride)
    #expect(members.count == StageUniforms.swiftLayout.count)
    for member in members {
        #expect(StageUniforms.swiftLayout[member.name] == member.offset, "\(member.name)")
    }
    // The finishing shader's uniforms are five plain numbers in a row.
    #expect(MemoryLayout<FinishUniforms>.stride == 20)
}

// MARK: The camera

@Test func theCameraLooksAtTheMiddleOfTheStage() {
    let camera = Camera(position: SIMD3(0, 0, 2.4))
    let middle = camera.viewProjection * SIMD4<Float>(0, 0, 0, 1)
    #expect(abs(middle.x / middle.w) < 1e-5)
    #expect(abs(middle.y / middle.w) < 1e-5)
    // In front of the camera, between the nearest and furthest things drawn.
    #expect(middle.z / middle.w > 0 && middle.z / middle.w < 1)
    #expect(abs(camera.depth(of: .zero) - 2.4) < 1e-5)
}

@Test func rightIsRightAndUpIsUp() {
    let camera = Camera(position: SIMD3(0, 0, 2.4))
    let right = camera.viewProjection * SIMD4<Float>(0.5, 0, 0, 1)
    let up = camera.viewProjection * SIMD4<Float>(0, 0.5, 0, 1)
    #expect(right.x / right.w > 0.1)
    #expect(up.y / up.w > 0.1)
}

@Test func thingsLookSmallerFurtherAway() {
    let camera = Camera(position: SIMD3(0, 0, 2.4))
    let near = camera.viewProjection * SIMD4<Float>(0.5, 0, 1, 1)
    let far = camera.viewProjection * SIMD4<Float>(0.5, 0, -1, 1)
    #expect(near.x / near.w > far.x / far.w)
}

@Test func theEdgeOfTheViewIsWhereTheFieldOfViewSaysItIs() {
    // 45 degrees top to bottom: at a distance of 2.4, the top edge is 0.994 up.
    let camera = Camera(position: SIMD3(0, 0, 2.4), aspect: 16.0 / 9.0)
    let halfHeight = 2.4 * tan(camera.fieldOfView / 2)
    let top = camera.viewProjection * SIMD4<Float>(0, halfHeight, 0, 1)
    let side = camera.viewProjection * SIMD4<Float>(halfHeight * camera.aspect, 0, 0, 1)
    #expect(abs(top.y / top.w - 1) < 1e-4)
    #expect(abs(side.x / side.w - 1) < 1e-4)
}

@Test func theCameraNeverStandsStillAndNeverWandersOff() {
    let drift = CameraDrift()
    var places: [SIMD3<Float>] = []
    for second in stride(from: 0.0, to: 600, by: 1) {
        let camera = drift.camera(at: second, aspect: 16.0 / 9.0, punchNow: 0)
        places.append(camera.position)
        // Always about its distance from the stage, in front of it, looking at it.
        let distance = simd_length(camera.position)
        #expect(distance > drift.distance * 0.95 && distance < drift.distance * 1.05)
        #expect(camera.position.z > drift.distance * 0.9)
        #expect(abs(camera.roll) <= drift.roll)
    }
    // Moving from each second to the next.
    for (one, next) in zip(places, places.dropFirst()) {
        #expect(simd_distance(one, next) > 1e-5)
    }
    // Ten minutes in, it isn't back where it was at any earlier whole second.
    let last = try! #require(places.last)
    #expect(places.dropLast().allSatisfy { simd_distance($0, last) > 1e-4 })
}

@Test func aBeatPunchesTheCameraIn() {
    let drift = CameraDrift()
    let resting = drift.camera(at: 12, aspect: 1.5, punchNow: 0)
    let punched = drift.camera(at: 12, aspect: 1.5, punchNow: 1)
    #expect(simd_length(punched.position) < simd_length(resting.position))
}

// MARK: Quality

@Test func theTiersAreTheOnesThatWereMeasured() {
    // docs/OUTPUT.md
    #expect(QualityTier.tier(for: .low, isLowPowerCard: false) == QualityTier(particleCount: 75_000, drawingWidth: 1_280, drawingHeight: 720))
    #expect(QualityTier.tier(for: .medium, isLowPowerCard: false).particleCount == 150_000)
    #expect(QualityTier.tier(for: .high, isLowPowerCard: false) == QualityTier(particleCount: 300_000, drawingWidth: 2_560, drawingHeight: 1_440))
    #expect(QualityTier.tier(for: .ultra, isLowPowerCard: false).particleCount == 1_000_000)
    // Auto: High, or Medium on a laptop's low-power graphics.
    #expect(QualityTier.tier(for: .auto, isLowPowerCard: false) == .high)
    #expect(QualityTier.tier(for: .auto, isLowPowerCard: true) == .medium)
}

@Test func thePictureIsTheViewsShapeAndNoBiggerThanTheTierAllows() {
    // A 5K screen at High: scaled down to 2560×1440's worth of pixels.
    let fiveK = QualityTier.high.pictureSize(forViewPixels: CGSize(width: 5_120, height: 2_880))
    #expect(fiveK.width == 2_560 && fiveK.height == 1_440)
    // A small window: drawn at its own size, never bigger.
    let small = QualityTier.high.pictureSize(forViewPixels: CGSize(width: 800, height: 600))
    #expect(small.width == 800 && small.height == 600)
    // A tall window keeps its shape.
    let tall = QualityTier.low.pictureSize(forViewPixels: CGSize(width: 2_000, height: 4_000))
    #expect(abs(Double(tall.height) / Double(tall.width) - 2) < 0.02)
    #expect(tall.width * tall.height <= 1_280 * 720 + 4_000)
    // Even numbers, and never nothing.
    let sliver = QualityTier.low.pictureSize(forViewPixels: CGSize(width: 1, height: 0))
    #expect(sliver.width >= 2 && sliver.height >= 2)
    #expect(fiveK.width % 2 == 0 && tall.width % 2 == 0 && tall.height % 2 == 0)
}

@Test func settingsStartWithTheFlashingLimitOn() throws {
    let settings = AcceleratorSettings()
    #expect(settings.limitsFlashing)
    #expect(settings.quality == .auto)
    #expect(settings.visual == 3)
    let saved = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(AcceleratorSettings.self, from: saved) == settings)
}

// MARK: The frame timer

@Test func theFrameTimerAveragesTheLastTwoSeconds() {
    let timer = FrameTimer()
    #expect(timer.summary == FrameTimer.Summary())
    for frame in 0..<200 {
        timer.frameBegan(at: Double(frame) / 60, preparingSeconds: 0.0005)
        timer.graphicsCardFinished(seconds: frame == 199 ? 0.012 : 0.006)
    }
    let summary = timer.summary
    #expect(abs(summary.framesPerSecond - 60) < 0.01)
    #expect(abs(summary.preparingMilliseconds - 0.5) < 0.001)
    #expect(abs(summary.graphicsCardMilliseconds - 6.05) < 0.01)
    #expect(abs(summary.slowestGraphicsCardMilliseconds - 12) < 0.001)
    #expect(abs(summary.longestGapMilliseconds - 1_000.0 / 60) < 0.001)
    #expect(summary.text == "60 fps (longest gap 17 ms) · graphics card 6.1 ms (slowest 12.0) · preparing 0.50 ms")
}

@Test func theFrameTimerShowsAMissedFrameThatTheAverageHides() {
    // Two seconds at 60 frames a second, with one frame a twentieth of a second late.
    let timer = FrameTimer()
    var time = 0.0
    for frame in 0..<120 {
        time += frame == 60 ? 1.0 / 60 + 0.05 : 1.0 / 60
        timer.frameBegan(at: time, preparingSeconds: 0.0005)
    }
    let summary = timer.summary
    #expect(summary.framesPerSecond > 58)
    #expect(abs(summary.longestGapMilliseconds - 66.7) < 0.1)
}
