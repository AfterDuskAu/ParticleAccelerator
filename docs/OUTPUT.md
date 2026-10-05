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

### The visuals

**2019 iMac, 2026-10-04.** The graphics card's time for a whole frame (sparks moved and drawn, glow, finishing), in a release build, each tier at its full size, in the busiest eight seconds of a busy song:

| Tier | Sparks | Picture | 3 Particle Wave | 4 Tendrils | 5 Fountain | 6 Starburst |
|---|---|---|---|---|---|---|
| Low | 75,000 | 1280×720 | 0.7 ms | 0.7 ms | 0.7 ms | 0.5 ms |
| Medium | 150,000 | 1920×1080 | 1.6 ms | 2.5 ms | 1.8 ms | 1.5 ms |
| High | 300,000 | 2560×1440 | 4.5 ms (slowest 11.8) | 7.0 ms (slowest 7.4) | 4.7 ms (slowest 5.5) | 4.5 ms (slowest 5.6) |
| Ultra | 1,000,000 | 3840×2160 | 30.1 ms | 35.5 ms | 27.7 ms | 22.9 ms |

High holds 60 fps on the iMac for all four (a frame allows 16.7 ms). Ultra needs a faster Mac.

**Earlier measurements of Visualizer 3,** High: 3.9 ms in its first version and 3.6 ms in its second (2026-10-03), before sparks were drawn with cores, streaks and blur discs. The new sparks cost about a millisecond.

**Could High draw a 4K picture on this iMac?** Measured with High's 300,000 sparks:

| Picture | 3 Particle Wave | 4 Tendrils | 5 Fountain | 6 Starburst |
|---|---|---|---|---|
| 3840×2160 | 10.4 ms (slowest 25.7) | 12.8 ms (slowest 13.8) | 9.9 ms (slowest 11.1) | 8.1 ms (slowest 10.2) |
| 5120×2880 | 16.8 ms | 18.5 ms | 16.8 ms | 13.7 ms |

Three of the four would hold 60 fps at 4K; Visualizer 3's busiest frames wouldn't. So High stays at 2560×1440, which the 5K screen doubles exactly in full screen. In a window the picture is already drawn at the window's own pixels. A sharper setting for the visuals that can afford it belongs with Auto quality.

**Later the same day,** after the owner had tuned Visualizers 4 and 5, Visualizer 6 was built a second time, and Visualizers 7 and 8 were added. Measured the same way, each as it's first shown (its standard), with the Mac busier than it was for the table above (other projects were building, and Visualizer 3 measured 5.3 ms where it had been 4.5):

| Tier | 3 Particle Wave | 4 Tendrils | 5 Fountain | 6 Starburst | 7 Corona | 8 Jets |
|---|---|---|---|---|---|---|
| Low | 0.8 ms | 0.7 ms | 0.8 ms | 1.1 ms | 0.7 ms | 0.6 ms |
| Medium | 2.0 ms | 2.0 ms | 2.9 ms | 3.7 ms | 1.1 ms | 1.6 ms |
| High | 5.3 ms (slowest 9.1) | 5.7 ms (slowest 8.2) | 8.0 ms (slowest 9.9) | 10.8 ms (slowest 12.4) | 2.1 ms (slowest 4.8) | 3.7 ms (slowest 6.5) |
| Ultra | 32.6 ms | 30.9 ms | 45.2 ms | 50.9 ms | 7.0 ms | 19.7 ms |

- **High holds 60 fps for all six.**
- **With the owner's own saved settings** for each (the sliders as they'd left them), High: 4.4, 6.7, 8.0, 10.0, 2.3 and 4.6 ms, and none slower than 11.9 ms.
- **Visualizer 5 costs more at the owner's standard** than at its base (8.0 ms against 4.7): the spray is wider and its sparks last twice as long, so more of them are on screen.
- **Visualizer 6 is the dearest now** (10.8 ms; its first design was 4.5). Every spark is in the air in three dimensions, and those away from the distance the camera is focused on are drawn as discs many pixels across. There's room at High, but less than the others have.
- **Visualizer 7 is the cheapest** (2.1 ms): the unlit part of each strand isn't drawn at all.
- **In the app,** High, with the made-up test song: 60 fps for each, and 2.1 ms (Visualizer 7), 3.4 ms (8), 7.1 ms (5) and 9.5 ms (6, with the owner's settings; slowest 14.4) on the graphics card. Visualizer 6 with long streaks is the one nearest the 16.7 ms a frame allows.

**That afternoon the owner set new standards for Visualizers 5, 7 and 8** (`VISUALS.md`), and they were measured before they went into the library. This time not with a song but with a made-up reading (every bar at the same level, a kick every half second), ten seconds drawn off screen and the last two averaged, each standard beside the one it replaces. The Mac was busy again (other projects were building: Visualizer 3 at High measured 6.0 ms).

| | 5, before | 5, now | 7, before | 7, now | 8, before | 8, now |
|---|---|---|---|---|---|---|
| Medium, loud (bars at 0.8) | 3.1 ms | 2.4 ms | 1.3 ms | 3.2 ms | 1.6 ms | 4.4 ms (slowest 7.7) |
| Medium, quieter (bars at 0.45) | 2.7 ms | 2.0 ms | 1.6 ms | 3.7 ms | 1.9 ms | 4.7 ms (slowest 7.7) |
| High, loud | 12.8 ms (slowest 37.0) | 5.9 ms (slowest 8.6) | 2.5 ms | 9.4 ms (slowest 11.3) | 3.3 ms | **17.9 ms (slowest 39.6)** |
| High, quieter | 9.0 ms (slowest 24.4) | 4.2 ms (slowest 7.1) | 2.5 ms | 8.2 ms (slowest 10.8) | 3.8 ms | **18.9 ms (slowest 46.0)** |

- **Visualizer 8 as the owner has it doesn't hold 60 fps at High on the iMac.** A frame allows 16.7 ms and it takes about 18, with frames of 40 ms and more. The likely reason, from its settings (not measured apart): nearly four times the sparks in the air (amount 3.74×), which last as long as they can, each leaving the longest streak (4×), so far more pixels are lit. At Medium it takes 4.5 ms.
  - The owner tuned it with the quality at Medium, so that's the picture they chose, and it was smooth for them.
  - It breaks rule 5 ("60 fps on the iMac at High") as a standard. It's left as the owner set it, and written up as a known limit in the changelog. Auto quality, which on the iMac still means High and still doesn't adapt, would show it dropping frames.
  - Music Organizer shows these three at Medium for this reason (`INTEGRATION.md`).
- **Visualizer 7 costs about four times what it did** (9.4 ms against 2.5 at High). It still holds 60 fps at High.
- **Visualizer 5 costs less than it did** at High: 5.9 ms, against 12.8 for the morning's standard in this run and 7.7 in the earlier one (its camera moved a lot, so its cost came and went).
- A run a few minutes earlier, with the Mac busier still, gave the same picture for the new standards: Visualizer 8 at High 18.4 ms (slowest 41.9), Visualizer 7 8.8 ms, Visualizer 5 5.9 ms. At Ultra, 95.9, 45.0 and 34.8 ms.
- **Flashing wasn't measured again** for the new standards.
- These aren't the table above's numbers over again: a made-up reading keeps every part of the picture busy at once, which a song doesn't. The comparison is between the columns here.

**2026-10-05, Visualizer 8's last standard** (a darker picture, less glow, only the strongest pitches). Measured the same way, but the owner was using Music Organizer at the time and the graphics card was shared: Visualizer 3 at High, the yardstick, read 12.2 ms in one pass and 5.7 in the next. So only the broad result is kept.

- **At High it's still over what a frame allows:** 16.7 and 27.2 ms in the two passes (slowest 59.5), against 20.1 and 35.7 for the standard before it in the same passes.
- **At Medium it's under:** 7.9 and 4.1 ms (slowest 13.7).
- Nothing here says the new standard costs more or less than the one before. What changed is how the picture is finished and which pitches show, not how many sparks there are. It wants measuring again with the Mac quiet.

**How a spark is drawn** was measured two ways (Visualizer 3, High): as one square of pixels with its shape worked out inside, 4.5 ms; as a four-cornered patch lying along its streak, which wastes no pixels, 7.4 ms. Drawing four corners for every spark costs more than the pixels saved, so it's one square, and streaks are kept short (at most 2% of the picture's height).

**Flashing** (the biggest swing in the whole picture's brightness within a third of a second, where 10% or more counts as a flash): Visualizer 3, 8%; Tendrils, 3%; Fountain, 3%; Starburst, 4%. Measured again later that day: Visualizer 3, 5%; Tendrils at the owner's standard, 1%; Fountain at the owner's standard, 5%; Starburst's second design, 5% (6% with the owner's settings); Corona, 7% at its base and 5% at its standard; Jets, 6% and 4%.

### Hearing the music

**2019 iMac, 2026-10-03:**

| What | Cost |
|---|---|
| Measuring the sound (FFT, bars, bands, beats), for each 60 fps frame | 0.012 ms on average, 0.08 ms at worst |
| The same, for a minute of music | 43 ms of processor time |
| The sound check window while it draws (SwiftUI, 60 fps, playing a song) | 15–21% of one processor core |
| The same window minimised, song still playing | 0.3% |

Measuring the sound costs almost nothing beside a frame's 16.7 ms. The sound check's cost is its SwiftUI drawing, which the visuals won't use: they draw with Metal.

### The visual, the sound check and the controls in one window

**2019 iMac, 2026-10-03,** High quality, the sample song playing, a 2676×1182 picture:

| What's showing | Frames a second | One processor core |
|---|---|---|
| The visual alone | 60 | about 7% |
| The visual over the sound check, as the sound check was first built | 44–50 | about 100% |
| The same, with the sound check drawing only shapes for each frame | 60 | 17–27% |
| The visual, the sound check and the controls panel | 60 | 25–50% |

The graphics card's time stayed at about 3 ms a frame throughout: the frames were lost on the processor. The sound check had been laying its whole view out afresh for every frame, words and all. Now the bars, meters and beat light are shapes drawn in one pass, and the words change four times a second.

At that point the stage still drew on the app's main thread, so heavy work elsewhere in the window cost it frames. It now draws on a thread of its own.

### The stage on a thread of its own

**2019 iMac, 2026-10-03.** Two copies of the app were given the same scripted load, one drawing the stage on the main thread (as it was) and one on its own thread. Both showed the visual, the sound check and the controls, at High quality in a 1578×602 picture with the sample song playing. Each stretch lasted twelve seconds, and the first three of each were left out.

| The window is… | Main thread: frames a second | longest wait between frames | Own thread: frames a second | longest wait |
|---|---|---|---|---|
| left alone | 59.7 | 63 ms | 60 | 17 ms |
| having a slider dragged (a new value 30 times a second) | 20 | 118 ms | 60 | 17 ms |
| the same, with the controls panel closing and opening twice a second | 24 | 265 ms | 60 | 19 ms |

At 60 frames a second a frame comes every 16.7 ms, so a longest wait of 17 to 19 ms means none was missed.

Dragging a slider was costing the main thread far more than it should, which matters for how the slider itself feels:

| While a slider is dragged | One processor core |
|---|---|
| As first built | about 100% (the main thread had no time to spare) |
| With the menus, the sound check and the colour pickers left alone unless they change | about 50% |

In the app itself, with all three showing in a 2834×1300 picture: 60 frames a second with a longest wait of 17 ms, 20 frames a second three seconds after the song is paused, and under 1% of a core with the window minimised.

### Keeping the picture in time with the sound

**2019 iMac, 2026-10-03:**

| What | Measured |
|---|---|
| How far ahead of the speakers a player's tap hears the sound | 0.46 s, steady |
| The size of the blocks a player's tap is handed | 2,260 samples (47 ms) |
| The output delay Core Audio reports for the owner's Bluetooth headphones | 195 ms |
| The output delay for the iMac's own speakers | to be read (they weren't in use) |
| How long a song stops when a tap is added to a player already playing | about 0.5 s |

The listener allows for all of these by itself. The timing control (± up to half a second) is for what Core Audio can't know, such as a TV that's slow to show the picture.
