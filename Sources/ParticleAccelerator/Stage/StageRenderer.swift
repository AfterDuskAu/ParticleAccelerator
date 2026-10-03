import CoreGraphics
import Metal
import QuartzCore

/// Draws the stage: the chosen visual's picture, then glow, then the finishing that
/// tones it to the screen.
///
/// The picture is drawn in floating-point numbers at the quality tier's size, so light
/// can be far brighter than white. The glow is made from smaller and smaller copies of
/// it, and the finishing step brings it all back to what a screen can show.
///
/// It needs no view: `draw` fills any texture, which is how the tests look at a frame.
/// Use it from one thread at a time.
final class StageRenderer {
    /// How many smaller copies the glow is made from: half, quarter, … size.
    static let glowLevels = 5

    let device: MTLDevice
    let timer = FrameTimer()
    private(set) var tier: QualityTier
    private(set) var pictureSize: (width: Int, height: Int) = (0, 0)
    /// The person's own changes to the visual's controls and colours. They take
    /// effect at the next frame.
    var values = ControlValues()

    private let queue: MTLCommandQueue
    private let visual: Visual
    private let glowDown: MTLRenderPipelineState
    private let glowUp: MTLRenderPipelineState
    private let finish: MTLRenderPipelineState
    private let smooth: MTLSamplerState
    private var picture: MTLTexture?
    private var glow: [MTLTexture] = []
    private var uniforms = StageUniforms()
    private var finishing = FinishUniforms()
    private var lastFrameTime: Double?

    /// Sets the stage up for one visual: compiles its shaders and makes its sparks.
    /// This takes a moment, so it's done away from the main thread.
    ///
    /// - Parameter screenFormat: the format of the texture `draw` will fill.
    init(device: MTLDevice, visualNumber: Int, tier: QualityTier, screenFormat: MTLPixelFormat) throws {
        self.device = device
        self.tier = tier
        guard let queue = device.makeCommandQueue() else {
            throw StageProblem(message: "The graphics card wouldn't take any work.")
        }
        self.queue = queue

        guard let visualType = StageRenderer.visuals.first(where: { $0.number == visualNumber }) else {
            throw StageProblem(message: "Visualizer \(visualNumber) isn't built yet.")
        }
        let library = try Self.compile(
            StageShaders.common + StageShaders.finishing + visualType.shaderSource,
            named: "Visualizer \(visualNumber)", device: device)
        visual = try visualType.init(device: device, library: library, particleCount: tier.particleCount)

        glowDown = try Self.screenPipeline(
            library: library, fragment: "glowDown", format: pictureFormat, adding: false, device: device)
        glowUp = try Self.screenPipeline(
            library: library, fragment: "glowUp", format: pictureFormat, adding: true, device: device)
        finish = try Self.screenPipeline(
            library: library, fragment: "finish", format: screenFormat, adding: false, device: device)

        let sampling = MTLSamplerDescriptor()
        sampling.minFilter = .linear
        sampling.magFilter = .linear
        sampling.sAddressMode = .clampToEdge
        sampling.tAddressMode = .clampToEdge
        guard let smooth = device.makeSamplerState(descriptor: sampling) else {
            throw StageProblem(message: "The graphics card couldn't set up its picture sampling.")
        }
        self.smooth = smooth
    }

    /// Every visual that's built, so far.
    static let visuals: [Visual.Type] = [ParticleWave.self, Tendrils.self, Fountain.self, Starburst.self]

    /// What a person can change about a visual, or nothing if it isn't built.
    static func controls(ofVisual number: Int) -> [VisualControl] {
        visuals.first { $0.number == number }?.controls ?? []
    }

    /// Every piece of shader source the stage can be asked to compile, with a name, for
    /// the test that compiles them all.
    static var allShaderSources: [(name: String, source: String)] {
        visuals.map {
            ("Visualizer \($0.number)", StageShaders.common + StageShaders.finishing + $0.shaderSource)
        }
    }

    static func compile(_ source: String, named name: String, device: MTLDevice) throws -> MTLLibrary {
        do {
            return try device.makeLibrary(source: source, options: nil)
        } catch {
            throw StageProblem(
                message: "\(name) can't start: its shaders didn't compile. \(error.localizedDescription)")
        }
    }

    // MARK: Size and quality

    /// Changes the quality. The picture's size changes at the next `resize`.
    func setTier(_ newTier: QualityTier) throws {
        guard newTier != tier else { return }
        try visual.setParticleCount(newTier.particleCount)
        tier = newTier
    }

    /// Fits the picture to a view of this many pixels and returns the picture's size.
    /// The frame handed to `draw` should be that size: the screen scales it up.
    @discardableResult
    func resize(forViewPixels view: CGSize) throws -> (width: Int, height: Int) {
        let size = tier.pictureSize(forViewPixels: view)
        guard size != pictureSize || picture == nil else { return size }
        picture = try makePicture(width: size.width, height: size.height)
        glow = []
        var width = size.width
        var height = size.height
        for _ in 0..<Self.glowLevels where width >= 16 && height >= 16 {
            width /= 2
            height /= 2
            glow.append(try makePicture(width: width, height: height))
        }
        pictureSize = size
        return size
    }

    private func makePicture(width: Int, height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pictureFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw StageProblem(
                message: "The graphics card couldn't make room for a \(width)×\(height) picture. Try a lower quality.")
        }
        return texture
    }

    // MARK: A frame

    /// Draws one frame into `screen`.
    /// - Parameters:
    ///   - reading: what the music is doing now.
    ///   - time: seconds on any steady clock.
    ///   - drawable: shown when the frame is done, if there is one.
    ///   - wait: true to wait until the graphics card has finished (for tests).
    func draw(
        reading: SoundReading, at time: Double, into screen: MTLTexture,
        presenting drawable: MTLDrawable? = nil, wait: Bool = false
    ) {
        let began = CACurrentMediaTime()
        guard let picture, !glow.isEmpty, let commands = queue.makeCommandBuffer() else { return }

        // A long gap (the window was hidden) counts as one ordinary frame.
        let seconds = min(0.1, max(0, lastFrameTime.map { time - $0 } ?? 1.0 / 60))
        lastFrameTime = time
        uniforms.time += Float(seconds)
        uniforms.seconds = Float(seconds)
        uniforms.pictureSize = SIMD2(Float(pictureSize.width), Float(pictureSize.height))
        uniforms.aspect = Float(pictureSize.width) / Float(pictureSize.height)
        uniforms.setBandLight(from: values, at: time)
        visual.prepare(&uniforms, finishing: &finishing, reading: reading, values: values)

        visual.draw(VisualFrame(commands: commands, uniforms: uniforms, picture: picture))
        encodeGlow(of: picture, commands)
        finishing.time = uniforms.time
        encodeFinish(picture: picture, into: screen, commands)

        commands.addCompletedHandler { [timer] finished in
            timer.graphicsCardFinished(seconds: finished.gpuEndTime - finished.gpuStartTime)
        }
        if let drawable { commands.present(drawable) }
        commands.commit()
        timer.frameBegan(at: time, preparingSeconds: CACurrentMediaTime() - began)
        if wait { commands.waitUntilCompleted() }
    }

    /// The glow: shrink the picture step by step, then grow it back, adding each step
    /// to the one above. What's left in the first glow picture is every width of blur
    /// at once.
    private func encodeGlow(of picture: MTLTexture, _ commands: MTLCommandBuffer) {
        var source = picture
        for level in glow {
            screenPass(glowDown, from: [source], into: level, keeping: false, commands)
            source = level
        }
        for index in stride(from: glow.count - 1, to: 0, by: -1) {
            screenPass(glowUp, from: [glow[index]], into: glow[index - 1], keeping: true, commands)
        }
    }

    private func encodeFinish(picture: MTLTexture, into screen: MTLTexture, _ commands: MTLCommandBuffer) {
        // Each glow step adds about as much light again, so share the strength out.
        var finishing = self.finishing
        finishing.glow /= Float(glow.count)
        screenPass(finish, from: [picture, glow[0]], into: screen, keeping: false, commands) { pass in
            pass.setFragmentBytes(&finishing, length: MemoryLayout<FinishUniforms>.stride, index: 0)
        }
    }

    /// One pass over a whole picture with a fragment shader.
    private func screenPass(
        _ pipeline: MTLRenderPipelineState, from sources: [MTLTexture], into target: MTLTexture,
        keeping: Bool, _ commands: MTLCommandBuffer,
        _ extra: (MTLRenderCommandEncoder) -> Void = { _ in }
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        // "Keeping" adds to what's already in the target; otherwise all of it is
        // drawn over, so there's nothing to load or clear.
        pass.colorAttachments[0].loadAction = keeping ? .load : .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let render = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        render.setRenderPipelineState(pipeline)
        for (index, source) in sources.enumerated() {
            render.setFragmentTexture(source, index: index)
        }
        render.setFragmentSamplerState(smooth, index: 0)
        extra(render)
        render.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        render.endEncoding()
    }

    private static func screenPipeline(
        library: MTLLibrary, fragment: String, format: MTLPixelFormat, adding: Bool, device: MTLDevice
    ) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: "wholeScreen"),
            let fragmentFunction = library.makeFunction(name: fragment)
        else {
            throw StageProblem(message: "A shader is missing: wholeScreen or \(fragment).")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        let colour = descriptor.colorAttachments[0]!
        colour.pixelFormat = format
        if adding {
            colour.isBlendingEnabled = true
            colour.sourceRGBBlendFactor = .one
            colour.destinationRGBBlendFactor = .one
            colour.sourceAlphaBlendFactor = .one
            colour.destinationAlphaBlendFactor = .one
        }
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
