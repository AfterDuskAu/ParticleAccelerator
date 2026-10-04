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

        // The same well-mixed number from 0 to 1 for the same spark and purpose, worked
        // out in whole numbers. The two above go through a sine, and on the iMac's
        // graphics card that came out as exactly 0 for about one spark in a thousand:
        // enough to draw a line of sparks straight up Visualizer 6 (2026-10-04). New
        // code uses this one.
        static float sparkChance(uint spark, uint purpose) {
            uint mixed = spark * 747796405u + purpose * 2891336453u + 1u;
            mixed = ((mixed >> ((mixed >> 28u) + 4u)) ^ mixed) * 277803737u;
            mixed = (mixed >> 22u) ^ mixed;
            return float(mixed) * (1.0 / 4294967296.0);
        }

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

        // One spark, as its vertex shader hands it on. A spark is drawn as one square
        // of pixels, and its shape is worked out inside the square: a hot core with a
        // soft skirt, drawn out into a streak if it's moving, or an even disc if it's
        // out of focus. That's how a camera sees a spark, which is what makes it look
        // real (the owner, 2026-10-04: "more realistic, more high def").
        //
        // One square for each spark was measured against a four-cornered patch lying
        // along the streak (2026-10-04, the iMac): the patches waste no pixels, but
        // drawing four corners for every spark took half as long again.
        struct SparkOut {
            float4 position [[position]];
            float size [[point_size]];
            // The square's width in pixels again: the size above is only for the
            // graphics card, and can't be read when the pixels are drawn.
            float width;
            half3 light;
            // Which way it's moving across the picture, and half its streak's length
            // in pixels.
            float2 along;
            float halfStreak;
            // Its own radius in pixels, and how far out of focus it is, from 0 to 1.
            float radius;
            float softness;
        };

        // Makes a spark from where it is and where it was a moment ago.
        //   stageRadius: how big it is on the stage.
        //   light: its colour times its brightness, as it is standing still and sharp.
        static SparkOut makeSpark(constant StageUniforms &stage, float3 place, float3 placeBefore,
                                  float stageRadius, float3 light) {
            SparkOut out;
            float4 now = stage.viewProjection * float4(place, 1.0);
            float4 before = stage.viewProjection * float4(placeBefore, 1.0);
            // Drawn midway, so the streak trails behind it.
            out.position = (now + before) * 0.5;
            float distance = max(now.w, 0.05);

            // Its size in pixels at its distance.
            float diameter = stageRadius / (distance * stage.tanHalfFieldOfView) * stage.pictureSize.y;
            // Out of focus: bigger and fainter.
            float blur = fabs(distance - stage.focusDistance) * stage.blurPerUnit * stage.pictureSize.y;
            float shown = clamp(diameter + blur, 1.6, 0.15 * stage.pictureSize.y);

            // How far it moved across the picture in that moment, in pixels. (The
            // picture's y runs downwards.) A streak is kept short: the square has to
            // hold it whichever way it points, and a long one wastes a lot of pixels.
            float2 moved = (now.xy / distance - before.xy / max(before.w, 0.05))
                * float2(0.5, -0.5) * stage.pictureSize;
            float far = length(moved);
            float streak = min(far, 0.022 * stage.pictureSize.y);
            out.along = far > 0.01 ? moved / far : float2(1.0, 0.0);
            out.halfStreak = streak * 0.5;
            out.radius = shown * 0.5;
            out.softness = saturate(blur / shown);
            out.size = shown + streak;
            out.width = out.size;

            // The same light over more pixels is fainter in each of them.
            float spread = max((diameter * diameter) / (shown * shown), 0.12);
            float drawnOut = shown / (shown + 0.6 * streak);
            out.light = half3(light * spread * drawnOut);
            return out;
        }

        // A spark that isn't there: nothing is drawn for it.
        static SparkOut noSpark() {
            SparkOut out;
            out.position = float4(0.0, 0.0, -10.0, 1.0);
            out.size = 0.0;
            out.width = 0.0;
            out.light = half3(0.0h);
            out.along = float2(1.0, 0.0);
            out.halfStreak = 0.0;
            out.radius = 1.0;
            out.softness = 0.0;
            return out;
        }

        fragment half4 sparkLight(SparkOut in [[stage_in]], float2 spot [[point_coord]]) {
            float2 fromMiddle = (spot - 0.5) * in.width;
            // How far this pixel is from the streak's line, in spark radiuses.
            float onStreak = clamp(dot(fromMiddle, in.along), -in.halfStreak, in.halfStreak);
            float away = length(fromMiddle - in.along * onStreak) / in.radius;
            // Sharp: a hot core with a soft skirt.
            float shape = exp(-away * away * 4.5);
            if (in.softness > 0.01) {
                // Out of focus: an even disc, a little brighter towards its rim, the
                // way a lens shows a point of light.
                float disc = (1.0 - smoothstep(0.82, 1.0, away)) * (0.2 + 0.1 * smoothstep(0.45, 0.9, away));
                shape = mix(shape, disc, in.softness);
            }
            return half4(in.light * half(shape), 1.0h);
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
