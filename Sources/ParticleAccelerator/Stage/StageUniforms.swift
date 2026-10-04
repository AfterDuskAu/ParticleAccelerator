import simd

/// What every shader is told each frame: where the camera is, what time it is, and
/// what the music is doing.
///
/// The Swift struct and the Metal one in `metalSource` must list the same things in
/// the same order. A test asks Metal where it put each one and checks it against Swift.
struct StageUniforms {
    /// Turns a place on the stage into a place in the picture.
    var viewProjection = matrix_identity_float4x4
    var cameraPosition = SIMD4<Float>(0, 0, 1, 0)
    /// The picture's size in pixels.
    var pictureSize = SIMD2<Float>(1_280, 720)
    /// The picture's width ÷ its height.
    var aspect: Float = 16.0 / 9.0
    /// The tangent of half the camera's field of view, for sizing sparks in pixels.
    var tanHalfFieldOfView: Float = 0.414
    /// Seconds since the stage started, and how long this frame lasts.
    var time: Float = 0
    var seconds: Float = 1.0 / 60
    /// The music, each from 0 to 1, already shaped by the visual's signal chains.
    var loudness: Float = 0
    var beat: Float = 0
    var beatPhase: Float = 0
    /// Depth of field: the distance that's sharp, and how much blur each unit of
    /// distance away from it adds (as a share of the picture's height).
    var focusDistance: Float = 2.4
    var blurPerUnit: Float = 0
    /// How quickly things fade with distance. 0 is no fog.
    var fog: Float = 0
    /// The six bands (two spare).
    var bands = SIMD8<Float>(repeating: 0)
    /// How many seconds ago each of the last four kicks landed.
    var kickAges = SIMD4<Float>(repeating: 1_000)
    /// Thirty-two numbers for the visual's own use.
    var controls = SIMD32<Float>(repeating: 0)
    /// The spectrum, bass first.
    var bars = SIMD64<Float>(repeating: 0)
    /// The six bands' colours as amounts of light: red, green, blue and a spare for
    /// each band, sub first (eight numbers spare at the end).
    var bandLight = SIMD32<Float>(repeating: 0)

    /// Fills in `bandLight` from a visual's colours at this moment: the person's own
    /// where they've picked one, or the made-up ones if they change by themselves.
    mutating func setBandLight(from values: ControlValues, visual: Int, at time: Double) {
        let colours = BandPalette(values, visual: visual).colours(at: time)
        for band in Band.allCases {
            let light = Band.light(of: colours[band.rawValue])
            bandLight[band.rawValue * 4] = light.x
            bandLight[band.rawValue * 4 + 1] = light.y
            bandLight[band.rawValue * 4 + 2] = light.z
        }
    }

    static let metalSource = """
        struct StageUniforms {
            float4x4 viewProjection;
            float4 cameraPosition;
            float2 pictureSize;
            float aspect;
            float tanHalfFieldOfView;
            float time;
            float seconds;
            float loudness;
            float beat;
            float beatPhase;
            float focusDistance;
            float blurPerUnit;
            float fog;
            float bands[8];
            float kickAges[4];
            float controls[32];
            float bars[64];
            float bandLight[32];
        };
        """

    /// Where Swift puts each member, by its Metal name, for the test.
    static let swiftLayout: [String: Int] = [
        "viewProjection": MemoryLayout<StageUniforms>.offset(of: \.viewProjection)!,
        "cameraPosition": MemoryLayout<StageUniforms>.offset(of: \.cameraPosition)!,
        "pictureSize": MemoryLayout<StageUniforms>.offset(of: \.pictureSize)!,
        "aspect": MemoryLayout<StageUniforms>.offset(of: \.aspect)!,
        "tanHalfFieldOfView": MemoryLayout<StageUniforms>.offset(of: \.tanHalfFieldOfView)!,
        "time": MemoryLayout<StageUniforms>.offset(of: \.time)!,
        "seconds": MemoryLayout<StageUniforms>.offset(of: \.seconds)!,
        "loudness": MemoryLayout<StageUniforms>.offset(of: \.loudness)!,
        "beat": MemoryLayout<StageUniforms>.offset(of: \.beat)!,
        "beatPhase": MemoryLayout<StageUniforms>.offset(of: \.beatPhase)!,
        "focusDistance": MemoryLayout<StageUniforms>.offset(of: \.focusDistance)!,
        "blurPerUnit": MemoryLayout<StageUniforms>.offset(of: \.blurPerUnit)!,
        "fog": MemoryLayout<StageUniforms>.offset(of: \.fog)!,
        "bands": MemoryLayout<StageUniforms>.offset(of: \.bands)!,
        "kickAges": MemoryLayout<StageUniforms>.offset(of: \.kickAges)!,
        "controls": MemoryLayout<StageUniforms>.offset(of: \.controls)!,
        "bars": MemoryLayout<StageUniforms>.offset(of: \.bars)!,
        "bandLight": MemoryLayout<StageUniforms>.offset(of: \.bandLight)!,
    ]
}

/// What the finishing shader is told: how the picture and its glow become the frame
/// on screen.
struct FinishUniforms {
    /// Brightens or darkens the whole picture before it's toned to the screen.
    var exposure: Float = 1
    /// How much glow is added.
    var glow: Float = 0.7
    /// How much the corners darken.
    var vignette: Float = 0.5
    /// Turned down by the flashing limit when the whole screen would flash too often.
    var dimming: Float = 1
    /// Changes every frame, so the fine grain that hides colour banding doesn't sit
    /// still.
    var time: Float = 0

    static let metalSource = """
        struct FinishUniforms {
            float exposure;
            float glow;
            float vignette;
            float dimming;
            float time;
        };
        """
}
