// pa-bench: how much can this Mac's graphics card draw? (docs/OUTPUT.md)
//
// Times the kinds of work the visuals are made of (glowing particles, a swirling
// background shader, and the glow) at several drawing sizes, then suggests a quality
// tier. Nothing is shown on screen and nothing is written to disk. It keeps the graphics
// card busy for about half a minute.
//
//     swift run -c release pa-bench
import AppKit
import Metal

setvbuf(stdout, nil, _IONBF, 0)

/// Each visual should leave half of a 60 fps frame (16.7 ms) for everything else.
let budgetMs = 8.0

let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Particle { float4 position; float4 velocity; };

    // Moves every particle a little through a wavy field, as a real visual would.
    kernel void stepParticles(device Particle *particles [[buffer(0)]],
                              constant float &time [[buffer(1)]],
                              uint i [[thread_position_in_grid]]) {
        Particle p = particles[i];
        float3 q = p.position.xyz;
        float3 push = float3(sin(q.y * 3.1 + time), sin(q.z * 2.7 + time * 1.3),
                             sin(q.x * 2.3 + time * 0.7));
        p.velocity.xyz = p.velocity.xyz * 0.98 + push * 0.002;
        q += p.velocity.xyz;
        if (length(q) > 2.0) q *= 0.1;
        p.position.xyz = q;
        particles[i] = p;
    }

    struct PointOut { float4 position [[position]]; float size [[point_size]]; float4 colour; };

    // Perspective: near particles are drawn bigger.
    vertex PointOut particleVertex(const device Particle *particles [[buffer(0)]],
                                   uint id [[vertex_id]]) {
        Particle p = particles[id];
        float depth = p.position.z + 3.0;
        PointOut out;
        out.position = float4(p.position.x / depth * 1.6, p.position.y / depth * 2.8, 0.5, 1.0);
        out.size = clamp(9.0 / depth, 1.5, 24.0);
        out.colour = float4(0.5, 0.3, 1.0, 0.25);
        return out;
    }

    // A soft round spark.
    fragment half4 particleFragment(PointOut in [[stage_in]], float2 spot [[point_coord]]) {
        float fade = smoothstep(1.0, 0.0, length(spot - 0.5) * 2.0);
        return half4(in.colour * fade);
    }

    float hash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
    float noise(float2 p) {
        float2 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + float2(1, 0)), f.x),
                   mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), f.x), f.y);
    }
    float layered(float2 p) {
        float total = 0, amount = 0.5;
        for (int k = 0; k < 6; k++) { total += amount * noise(p); p *= 2.02; amount *= 0.5; }
        return total;
    }

    struct ScreenOut { float4 position [[position]]; float2 uv; };

    vertex ScreenOut wholeScreen(uint id [[vertex_id]]) {
        float2 uv = float2((id << 1) & 2, id & 2);
        ScreenOut out;
        out.position = float4(uv * 2.0 - 1.0, 0, 1);
        out.uv = uv;
        return out;
    }

    // Red ink swirling, mirrored left and right, like Visualizer 1's background.
    fragment half4 ink(ScreenOut in [[stage_in]], constant float &time [[buffer(0)]]) {
        float2 p = float2(abs(in.uv.x - 0.5), in.uv.y) * 3.0;
        float2 q = float2(layered(p + time * 0.1), layered(p + 5.2));
        float2 r = float2(layered(p + 4.0 * q + 1.7 + time * 0.15), layered(p + 4.0 * q + 9.2));
        float v = layered(p + 4.0 * r);
        return half4(half3(v * 1.4, v * 0.15, v * 0.1), 1);
    }

    // One sideways pass of a soft blur; the glow is four of them.
    kernel void blur(texture2d<half, access::read> source [[texture(0)]],
                     texture2d<half, access::write> target [[texture(1)]],
                     uint2 g [[thread_position_in_grid]]) {
        half4 sum = 0;
        int last = int(source.get_width()) - 1;
        for (int k = -6; k <= 6; k++) sum += source.read(uint2(clamp(int(g.x) + k, 0, last), g.y));
        target.write(sum / 13.0h, g);
    }
    """

guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    print("This Mac has no Metal graphics card, so the visuals can't run here.")
    exit(1)
}

let library: MTLLibrary
do {
    library = try device.makeLibrary(source: shaderSource, options: nil)
} catch {
    print("The test shaders didn't compile: \(error.localizedDescription)")
    exit(1)
}

func function(_ name: String) -> MTLFunction { library.makeFunction(name: name)! }

func renderPipeline(_ vertex: String, _ fragment: String, additive: Bool) throws
    -> MTLRenderPipelineState
{
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = function(vertex)
    descriptor.fragmentFunction = function(fragment)
    let colour = descriptor.colorAttachments[0]!
    colour.pixelFormat = .rgba16Float
    if additive {  // sparks add up to light, as in all the reference pictures
        colour.isBlendingEnabled = true
        colour.sourceRGBBlendFactor = .one
        colour.destinationRGBBlendFactor = .one
        colour.sourceAlphaBlendFactor = .one
        colour.destinationAlphaBlendFactor = .one
    }
    return try device.makeRenderPipelineState(descriptor: descriptor)
}

let stepPipeline: MTLComputePipelineState
let blurPipeline: MTLComputePipelineState
let particlePipeline: MTLRenderPipelineState
let inkPipeline: MTLRenderPipelineState
do {
    stepPipeline = try device.makeComputePipelineState(function: function("stepParticles"))
    blurPipeline = try device.makeComputePipelineState(function: function("blur"))
    particlePipeline = try renderPipeline("particleVertex", "particleFragment", additive: true)
    inkPipeline = try renderPipeline("wholeScreen", "ink", additive: false)
} catch {
    print("The graphics card refused the test shaders: \(error.localizedDescription)")
    exit(1)
}

/// Right-aligns a column of numbers.
func padded(_ text: String, _ width: Int) -> String {
    String(repeating: " ", count: max(0, width - text.count)) + text
}

func picture(_ width: Int, _ height: Int) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
    descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
    descriptor.storageMode = .private
    return device.makeTexture(descriptor: descriptor)!
}

/// The graphics card's own time per frame, averaged over 60 frames after 10 to warm up.
func timePerFrame(_ encode: (MTLCommandBuffer, Float) -> Void) -> Double {
    var total = 0.0
    for frame in 0..<70 {
        let commands = queue.makeCommandBuffer()!
        encode(commands, Float(frame) / 60)
        commands.commit()
        commands.waitUntilCompleted()
        if frame >= 10 { total += commands.gpuEndTime - commands.gpuStartTime }
    }
    return total / 60 * 1000
}

func particles(_ count: Int, _ width: Int, _ height: Int) -> Double {
    var start = [SIMD4<Float>]()
    start.reserveCapacity(count * 2)
    for _ in 0..<count {
        start.append(
            SIMD4(.random(in: -1...1), .random(in: -1...1), .random(in: -1...1), 1))
        start.append(.zero)
    }
    let buffer = device.makeBuffer(bytes: start, length: count * 32, options: .storageModeShared)!
    let target = picture(width, height)
    return timePerFrame { commands, time in
        var time = time
        let compute = commands.makeComputeCommandEncoder()!
        compute.setComputePipelineState(stepPipeline)
        compute.setBuffer(buffer, offset: 0, index: 0)
        compute.setBytes(&time, length: 4, index: 1)
        compute.dispatchThreads(
            MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
        compute.endEncoding()
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let draw = commands.makeRenderCommandEncoder(descriptor: pass)!
        draw.setRenderPipelineState(particlePipeline)
        draw.setVertexBuffer(buffer, offset: 0, index: 0)
        draw.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
        draw.endEncoding()
    }
}

func background(_ width: Int, _ height: Int) -> Double {
    let target = picture(width, height)
    return timePerFrame { commands, time in
        var time = time
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        let draw = commands.makeRenderCommandEncoder(descriptor: pass)!
        draw.setRenderPipelineState(inkPipeline)
        draw.setFragmentBytes(&time, length: 4, index: 0)
        draw.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        draw.endEncoding()
    }
}

/// The glow is worked out at half size, so it's timed at half size.
func glow(_ width: Int, _ height: Int) -> Double {
    let a = picture(width / 2, height / 2)
    let b = picture(width / 2, height / 2)
    return timePerFrame { commands, _ in
        for (source, target) in [(a, b), (b, a), (a, b), (b, a)] {
            let compute = commands.makeComputeCommandEncoder()!
            compute.setComputePipelineState(blurPipeline)
            compute.setTexture(source, index: 0)
            compute.setTexture(target, index: 1)
            compute.dispatchThreads(
                MTLSize(width: width / 2, height: height / 2, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            compute.endEncoding()
        }
    }
}

// MARK: - This Mac

func gigabytes(_ bytes: UInt64) -> String { String(format: "%.0f GB", Double(bytes) / 1e9) }

print("Graphics card: \(device.name)")
print("  memory it can use: \(gigabytes(device.recommendedMaxWorkingSetSize))"
    + (device.hasUnifiedMemory ? " (shared with the computer: Apple Silicon)" : ""))
var widest = (width: 1920, height: 1080)
for screen in NSScreen.screens {
    let scale = screen.backingScaleFactor
    let width = Int(screen.frame.width * scale)
    let height = Int(screen.frame.height * scale)
    // Above 1, bright sparks can be shown brighter than white (EDR): XDR screens reach 16.
    let headroom = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
    print(
        "Screen: \(screen.localizedName), \(width)×\(height) pixels, "
            + "up to \(screen.maximumFramesPerSecond) fps"
            + (headroom > 1 ? String(format: ", brighter than white up to %.1f×", headroom) : ""))
    if width * height > widest.width * widest.height { widest = (width, height) }
}

// MARK: - Measuring

struct Tier {
    let name: String
    let particles: Int
    let width: Int
    let height: Int
}

// Kept in step with docs/OUTPUT.md.
let tiers = [
    Tier(name: "Ultra", particles: 1_000_000, width: 3840, height: 2160),
    Tier(name: "High", particles: 300_000, width: 2560, height: 1440),
    Tier(name: "Medium", particles: 150_000, width: 1920, height: 1080),
    Tier(name: "Low", particles: 75_000, width: 1280, height: 720),
]

var sizes = [(1280, 720), (1920, 1080), (2560, 1440), (3840, 2160)]
if widest.width * widest.height > 3840 * 2160 { sizes.append((widest.width, widest.height)) }
let counts = [75_000, 150_000, 300_000, 1_000_000, 3_000_000]

struct Key: Hashable {
    let width: Int
    let count: Int
}
var particleMs: [Key: Double] = [:]
var backgroundMs: [Int: Double] = [:]
var glowMs: [Int: Double] = [:]

print("\nMilliseconds per frame. Smooth 60 fps allows 16.7; a visual should use under \(Int(budgetMs)).")
for (width, height) in sizes {
    print("-- drawing at \(width)×\(height)")
    for count in counts {
        let ms = particles(count, width, height)
        particleMs[Key(width: width, count: count)] = ms
        print("   \(padded(count.formatted(), 9)) glowing particles  " + String(format: "%7.2f", ms))
    }
    backgroundMs[width] = background(width, height)
    glowMs[width] = glow(width, height)
    print(String(format: "   swirling background          %7.2f", backgroundMs[width]!))
    print(String(format: "   glow                         %7.2f", glowMs[width]!))
}

// A visual is either mostly particles or mostly a background shader, each with glow.
func fits(_ tier: Tier, budget: Double) -> Bool {
    guard let sparks = particleMs[Key(width: tier.width, count: tier.particles)],
        let shader = backgroundMs[tier.width], let glowTime = glowMs[tier.width]
    else { return false }
    return max(sparks, shader) + glowTime <= budget
}

print("")
for (fps, budget) in [(60, budgetMs), (120, budgetMs / 2)] {
    if let best = tiers.first(where: { fits($0, budget: budget) }) {
        print(
            "Suggested at \(fps) fps: \(best.name): \(best.particles.formatted()) particles, "
                + "drawing at \(best.width)×\(best.height)")
    } else {
        print("Suggested at \(fps) fps: below Low; try 30 fps")
    }
}
