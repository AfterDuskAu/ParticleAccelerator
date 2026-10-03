# Output: from the iMac to a Mac Studio

Particle Accelerator should look its best on whatever Mac it's on. An older Mac or a laptop on battery gets a lighter version, and a Mac Studio on a big 4K or 6K screen gets millions of particles at 120 fps, with highlights brighter than white on screens that can show them.

## Quality tiers

| Tier | Particles per visual | Drawing size | For |
|---|---|---|---|
| Low | 75,000 | 1280×720 | older Macs, a laptop on battery |
| Medium | 150,000 | 1920×1080 | the iMac at 120 fps (it has no 120 Hz screen), Apple Silicon laptops |
| High | 300,000 | 2560×1440 | **the iMac at 60 fps** (measured) |
| Ultra | 1,000,000 or more | 3840×2160 up to the screen's own size | Apple Silicon Pro, Max and Ultra chips, such as a Mac Studio (to be measured) |
| Auto | picks a tier from `pa-bench`-style checks and adapts as it plays | | the default |

**The drawing size** is the size of the picture the visual is drawn at, before it's scaled to the screen. Glowing, soft pictures scale up well, so a 2560×1440 drawing looks fine on the iMac's 5K screen.

**Auto** starts from the tier the Mac's graphics card suggests. While it plays, it watches each frame's time: if frames run late for about a second, it lowers the drawing size and then the particle count, and it raises them again after a few calm seconds. The person never sees a stutter for long.

## Output options (planned)

- **Frame rate:** 30, 60, 120, or the screen's best. 120 needs a ProMotion screen, such as an Apple Silicon MacBook Pro or a Pro Display XDR.
- **Drawing size:** a fixed size (720p, 1080p, 1440p, 4K, 5K, 6K), a percentage of the screen, or Auto.
- **Brighter than white (EDR):** on screens that can, the brightest sparks really glow. Measured headroom: the iMac's screen 2.0× (2026-10-03). Apple's XDR screens go much higher; measure one with `pa-bench` before promising a number.
- **Where it shows:** in a window, full screen on any screen, or an output screen (a TV, a projector, a second monitor) with the controls on the main screen.
- **Recording a video:** draws the visual frame by frame from a song file, at any size and frame rate (4K 60 fps even on the iMac, just slower than real time). The song's own sound goes in unchanged, and the file is saved where the person chooses. This is how a slower Mac can still make a full-quality result.
- **Effects that cost more:** depth of field, trails, motion blur and fog switch off first when a Mac is short of power.

## Measured

`pa-bench` (`swift run -c release pa-bench`) times glowing particles, a swirling background shader and the glow at several drawing sizes. A visual should use under 8 ms of a 60 fps frame's 16.7 ms.

**2019 iMac, AMD Radeon Pro 570X (4 GB), 5K screen at 60 Hz, 2026-10-03:**

| Work per frame | 1280×720 | 1920×1080 | 2560×1440 | 3840×2160 | 5120×2880 |
|---|---|---|---|---|---|
| 75,000 particles | 1.3 ms | 1.5 ms | 1.5 ms | 1.9 ms | 2.3 ms |
| 150,000 particles | 2.3 ms | 2.3 ms | 2.6 ms | 3.0 ms | 3.5 ms |
| 300,000 particles | 4.2 ms | 4.5 ms | 4.8 ms | 5.1 ms | 6.0 ms |
| 1,000,000 particles | 13.5 ms | 13.9 ms | 13.9 ms | 15.2 ms | 16.4 ms |
| 3,000,000 particles | 39.2 ms | 38.4 ms | 40.6 ms | 41.6 ms | 44.3 ms |
| Swirling background | 1.2 ms | 2.6 ms | 4.6 ms | 10.3 ms | 18.3 ms |
| Glow | 0.2 ms | 0.4 ms | 0.7 ms | 1.6 ms | 2.7 ms |

Suggested: **High at 60 fps**, Medium at 120 fps. The particle count matters far more than the drawing size; the background shader is the reverse.

To add: a Mac Studio, an Apple Silicon laptop. Run `pa-bench` on it and add its table here.

### Hearing the music

**2019 iMac, 2026-10-03:**

| What | Cost |
|---|---|
| Measuring the sound (FFT, bars, bands, beats), for each 60 fps frame | 0.012 ms on average, 0.08 ms at worst |
| The same, for a minute of music | 43 ms of processor time |
| The sound check window while it draws (SwiftUI, 60 fps, playing a song) | 15–21% of one processor core |
| The same window minimised, song still playing | 0.3% |

Measuring the sound costs almost nothing beside a frame's 16.7 ms. The sound check's cost is its SwiftUI drawing, which the visuals won't use: they draw with Metal.
