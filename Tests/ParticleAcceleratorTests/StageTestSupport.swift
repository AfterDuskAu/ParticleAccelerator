import Metal
import Testing
import simd

@testable import ParticleAccelerator

/// Some CI machines have no graphics card that Metal can use.
let graphicsCard: MTLDevice? = MTLCreateSystemDefaultDevice()
let hasGraphicsCard = graphicsCard != nil
let noGraphicsCard: Comment = "This computer has no Metal graphics card."

/// A finished frame, read back from the graphics card.
struct Frame {
    let width: Int
    let height: Int
    /// Blue, green, red, alpha for each pixel, row by row from the top.
    let pixels: [UInt8]

    /// How bright a pixel is, from 0 to 1.
    func brightness(x: Int, y: Int) -> Double {
        let start = (y * width + x) * 4
        return (Double(pixels[start]) + Double(pixels[start + 1]) + Double(pixels[start + 2])) / (3 * 255)
    }

    /// The average brightness of a rectangle given in shares of the frame (0 to 1),
    /// with (0, 0) at the top left.
    func brightness(left: Double, top: Double, right: Double, bottom: Double) -> Double {
        var total = 0.0
        var count = 0
        for y in Int(top * Double(height))..<max(Int(top * Double(height)) + 1, Int(bottom * Double(height))) {
            for x in Int(left * Double(width))..<max(Int(left * Double(width)) + 1, Int(right * Double(width))) {
                total += brightness(x: min(x, width - 1), y: min(y, height - 1))
                count += 1
            }
        }
        return total / Double(max(count, 1))
    }

    /// The average red, green and blue of a rectangle given the same way, each from 0
    /// to 1.
    func colour(left: Double, top: Double, right: Double, bottom: Double) -> (red: Double, green: Double, blue: Double) {
        var red = 0.0, green = 0.0, blue = 0.0
        var count = 0.0
        for y in Int(top * Double(height))..<min(height, max(Int(top * Double(height)) + 1, Int(bottom * Double(height)))) {
            for x in Int(left * Double(width))..<min(width, max(Int(left * Double(width)) + 1, Int(right * Double(width)))) {
                let start = (y * width + x) * 4
                blue += Double(pixels[start])
                green += Double(pixels[start + 1])
                red += Double(pixels[start + 2])
                count += 255
            }
        }
        return (red / max(count, 1), green / max(count, 1), blue / max(count, 1))
    }

    /// How bright the brightest pixel is, from 0 to 1.
    var brightestPixel: Double {
        var most: UInt8 = 0
        for start in stride(from: 0, to: pixels.count, by: 4) {
            most = max(most, pixels[start], pixels[start + 1], pixels[start + 2])
        }
        return Double(most) / 255
    }

    /// The average brightness of each row, top to bottom.
    var rows: [Double] {
        (0..<height).map { y in
            (0..<width).reduce(0.0) { $0 + brightness(x: $1, y: y) } / Double(width)
        }
    }
}

/// A visual's base settings: its plain first ones, which a visual's own tests look at.
/// (Its standard may be anything the owner has since set.)
func baseValues(ofVisual visual: Int) -> ControlValues {
    var values = ControlValues()
    values.resetToBase(visual: visual)
    return values
}

/// Draws frames of a visual without a window, and hands back the last one. The visual
/// starts at its base settings.
final class TestStage {
    let renderer: StageRenderer
    private let device: MTLDevice
    private let screen: MTLTexture
    private let width: Int
    private let height: Int
    private var time = 0.0

    init(width: Int = 640, height: Int = 360, particleCount: Int = 30_000, visual: Int = 3) throws {
        device = graphicsCard!
        self.width = width
        self.height = height
        let tier = QualityTier(particleCount: particleCount, drawingWidth: width, drawingHeight: height)
        renderer = try StageRenderer(
            device: device, visualNumber: visual, tier: tier, screenFormat: .bgra8Unorm)
        try renderer.resize(forViewPixels: CGSize(width: width, height: height))
        renderer.values = baseValues(ofVisual: visual)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        screen = device.makeTexture(descriptor: descriptor)!
    }

    /// Draws this many frames, a sixtieth of a second apart, to the same reading.
    func draw(frames: Int, reading: SoundReading) {
        for _ in 0..<frames {
            time += 1.0 / 60
            renderer.draw(reading: reading, at: time, into: screen, wait: true)
        }
    }

    /// The frame last drawn.
    func lastFrame() -> Frame {
        let length = width * height * 4
        let buffer = device.makeBuffer(length: length, options: .storageModeShared)!
        let commands = device.makeCommandQueue()!.makeCommandBuffer()!
        let copy = commands.makeBlitCommandEncoder()!
        copy.copy(
            from: screen, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer,
            destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: length)
        copy.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let bytes = buffer.contents().bindMemory(to: UInt8.self, capacity: length)
        return Frame(width: width, height: height, pixels: Array(UnsafeBufferPointer(start: bytes, count: length)))
    }
}

/// A reading with music in it: a tall peak a quarter of the way along the spectrum
/// and nothing much elsewhere.
func readingWithAPeak(loudness: Float = 0.8) -> SoundReading {
    var reading = SoundReading.silence
    for bar in 12...20 { reading.bars[bar] = 1 }
    reading.loudness = loudness
    reading.bands.kick = 0.8
    reading.seconds = 10
    return reading
}
