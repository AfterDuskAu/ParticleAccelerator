import Foundation
import Metal

/// What a visual is handed to draw one frame.
struct VisualFrame {
    /// The frame's list of work for the graphics card.
    let commands: MTLCommandBuffer
    /// The camera, the time and the music, as the visual left them in `prepare`.
    var uniforms: StageUniforms
    /// The floating-point picture to draw into. The stage adds glow and finishing
    /// afterwards.
    let picture: MTLTexture
}

/// One visual: what it draws and how it moves with the music. Each lives in a file of
/// its own in this folder.
protocol Visual: AnyObject {
    /// The visual's number (docs/VISUALS.md).
    static var number: Int { get }
    /// Its Metal shaders, compiled after `StageShaders.common`.
    static var shaderSource: String { get }
    /// What a person can change about it, in the order the controls panel shows them.
    static var controls: [VisualControl] { get }
    /// Its standard, where that differs from its controls' base settings: each
    /// control's key and its setting. This is how the owner's "Set Standard" is kept in
    /// the library, so the visual looks the same in any app.
    static var standard: [String: Float] { get }
    /// True if its controls start locked: the owner has settled it, and nothing should
    /// be moved by accident.
    static var startsLocked: Bool { get }

    /// - Parameters:
    ///   - library: the visual's shaders, compiled.
    ///   - particleCount: how many particles the quality tier allows.
    init(device: MTLDevice, library: MTLLibrary, particleCount: Int) throws

    /// Changes how many particles it uses, when the quality changes.
    func setParticleCount(_ count: Int) throws

    /// Gets a frame's uniforms ready: the camera, and the music put through the
    /// visual's signal chains. `time`, `seconds`, `pictureSize` and `aspect` are
    /// already filled in.
    /// - Parameters:
    ///   - finishing: how the picture and its glow become the frame on screen. The
    ///     visual sets the glow, brightness and dark corners it wants.
    ///   - values: the person's own changes to the controls and colours.
    func prepare(
        _ uniforms: inout StageUniforms, finishing: inout FinishUniforms, reading: SoundReading,
        values: ControlValues)

    /// Moves the visual on by one frame and draws it into the picture.
    func draw(_ frame: VisualFrame)
}

extension Visual {
    static var standard: [String: Float] { [:] }
    static var startsLocked: Bool { false }
}

/// The format of the picture visuals draw into: floating-point, so light can be far
/// brighter than white before the glow and finishing bring it back to the screen.
let pictureFormat = MTLPixelFormat.rgba16Float

/// Something that stopped the stage from drawing, said so a person can act on it.
struct StageProblem: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

extension MTLDevice {
    /// A pipeline for drawing light into the picture: everything adds up, as light does.
    func makeLightPipeline(library: MTLLibrary, vertex: String, fragment: String) throws
        -> MTLRenderPipelineState
    {
        guard let vertexFunction = library.makeFunction(name: vertex),
            let fragmentFunction = library.makeFunction(name: fragment)
        else {
            throw StageProblem(message: "A shader is missing: \(vertex) or \(fragment).")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        let colour = descriptor.colorAttachments[0]!
        colour.pixelFormat = pictureFormat
        colour.isBlendingEnabled = true
        colour.sourceRGBBlendFactor = .one
        colour.destinationRGBBlendFactor = .one
        colour.sourceAlphaBlendFactor = .one
        colour.destinationAlphaBlendFactor = .one
        return try makeRenderPipelineState(descriptor: descriptor)
    }

    /// A pipeline that dims what's already in the picture: each pixel is multiplied by
    /// what the fragment shader returns. A visual that leaves trails dims the last
    /// frame a little with it before drawing the new one on top.
    func makeDimmingPipeline(library: MTLLibrary, vertex: String, fragment: String) throws
        -> MTLRenderPipelineState
    {
        guard let vertexFunction = library.makeFunction(name: vertex),
            let fragmentFunction = library.makeFunction(name: fragment)
        else {
            throw StageProblem(message: "A shader is missing: \(vertex) or \(fragment).")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        let colour = descriptor.colorAttachments[0]!
        colour.pixelFormat = pictureFormat
        colour.isBlendingEnabled = true
        colour.sourceRGBBlendFactor = .zero
        colour.destinationRGBBlendFactor = .sourceColor
        colour.sourceAlphaBlendFactor = .zero
        colour.destinationAlphaBlendFactor = .one
        return try makeRenderPipelineState(descriptor: descriptor)
    }
}
