/// The Metal shaders the stage itself uses, kept as text and compiled when the stage
/// starts (CLAUDE.md rule 7: `swift build` doesn't compile .metal files). Each visual
/// adds its own after these. A test compiles them all.
enum StageShaders {
    /// What every shader starts with: Metal's own library, the stage's uniforms, and a
    /// few helpers.
    static let common = """
        #include <metal_stdlib>
        using namespace metal;

        \(StageUniforms.metalSource)

        // The same "random" number between 0 and 1 for the same input, every time.
        static float chance(float n) { return fract(sin(n) * 43758.5453123); }
        static float chance2(float a, float b) { return fract(sin(a * 127.1 + b * 311.7) * 43758.5453123); }

        // The spectrum's height at a place along it, from 0 (bass) to 1 (highs), read
        // smoothly between the 64 bars.
        static float spectrumAt(constant StageUniforms &stage, float along) {
            float place = clamp(along, 0.0, 1.0) * 63.0;
            int bar = min(int(place), 62);
            return mix(stage.bars[bar], stage.bars[bar + 1], place - float(bar));
        }

        // A band's colour as light: 0 is the sub, 5 is the air.
        static float3 bandLightOf(constant StageUniforms &stage, int band) {
            return float3(stage.bandLight[band * 4], stage.bandLight[band * 4 + 1], stage.bandLight[band * 4 + 2]);
        }
        """

    /// Glow and finishing: the last steps of every frame, whatever the visual.
    static let finishing = """
        \(FinishUniforms.metalSource)

        struct ScreenOut { float4 position [[position]]; float2 uv; };

        // One big triangle that covers the whole picture.
        vertex ScreenOut wholeScreen(uint id [[vertex_id]]) {
            float2 corner = float2((id << 1) & 2, id & 2);
            ScreenOut out;
            out.position = float4(corner * 2.0 - 1.0, 0, 1);
            out.uv = float2(corner.x, 1.0 - corner.y);
            return out;
        }

        // Glow, step 1: shrink the picture to half size, blurring a little as it goes.
        // Done several times over, each smaller picture is a wider blur.
        fragment half4 glowDown(ScreenOut in [[stage_in]],
                                texture2d<half> source [[texture(0)]],
                                sampler smooth [[sampler(0)]]) {
            float2 texel = 1.0 / float2(source.get_width(), source.get_height());
            half4 sum = source.sample(smooth, in.uv) * 4.0h;
            sum += source.sample(smooth, in.uv + texel * float2(-1, -1));
            sum += source.sample(smooth, in.uv + texel * float2( 1, -1));
            sum += source.sample(smooth, in.uv + texel * float2(-1,  1));
            sum += source.sample(smooth, in.uv + texel * float2( 1,  1));
            return sum / 8.0h;
        }

        // Glow, step 2: grow each blurred picture back up and add it to the one above,
        // so the glow has a tight halo and a wide one together.
        fragment half4 glowUp(ScreenOut in [[stage_in]],
                              texture2d<half> source [[texture(0)]],
                              sampler smooth [[sampler(0)]]) {
            float2 texel = 1.0 / float2(source.get_width(), source.get_height());
            half4 sum = source.sample(smooth, in.uv + texel * float2(-1.0, 0.0));
            sum += source.sample(smooth, in.uv + texel * float2(-0.5, 0.5)) * 2.0h;
            sum += source.sample(smooth, in.uv + texel * float2(0.0, 1.0));
            sum += source.sample(smooth, in.uv + texel * float2(0.5, 0.5)) * 2.0h;
            sum += source.sample(smooth, in.uv + texel * float2(1.0, 0.0));
            sum += source.sample(smooth, in.uv + texel * float2(0.5, -0.5)) * 2.0h;
            sum += source.sample(smooth, in.uv + texel * float2(0.0, -1.0));
            sum += source.sample(smooth, in.uv + texel * float2(-0.5, -0.5)) * 2.0h;
            return sum / 12.0h;
        }

        // The last step: the picture plus its glow, toned to what a screen can show.
        fragment half4 finish(ScreenOut in [[stage_in]],
                              texture2d<half> picture [[texture(0)]],
                              texture2d<half> glow [[texture(1)]],
                              sampler smooth [[sampler(0)]],
                              constant FinishUniforms &finishing [[buffer(0)]]) {
            float3 light = float3(picture.sample(smooth, in.uv).rgb)
                + float3(glow.sample(smooth, in.uv).rgb) * finishing.glow;

            // Darker towards the corners.
            float2 fromCentre = in.uv - 0.5;
            light *= 1.0 - finishing.vignette * dot(fromCentre, fromCentre) * 2.0;
            light *= finishing.exposure * finishing.dimming;

            // Light can be any brightness; a screen stops at white. Bright light is
            // bent down to fit, keeping its colour, and only the very brightest
            // bleaches towards white, the way a hot spark does.
            float brightest = max(light.r, max(light.g, light.b));
            float fitted = 1.0 - exp(-brightest);
            float3 shown = light * (fitted / max(brightest, 0.00001));
            shown = mix(shown, float3(fitted), 0.75 * smoothstep(1.2, 7.0, brightest));

            // The screen's own brightness curve (sRGB).
            shown = mix(shown * 12.92, 1.055 * pow(shown, float3(1.0 / 2.4)) - 0.055,
                        step(0.0031308, shown));

            // Fine grain, less than one step of brightness, so smooth glows don't show
            // bands.
            float grain = fract(sin(dot(in.position.xy, float2(12.9898, 78.233))
                                    + finishing.time) * 43758.5453);
            shown += (grain - 0.5) / 255.0;
            return half4(half3(shown), 1.0h);
        }
        """
}
