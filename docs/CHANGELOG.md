# Changelog

## 0.1.0 (in progress): setting up

2026-10-03. The owner asked for a music visualizer as a project of its own, named Particle Accelerator, to be added to Music Organizer when it's done. The plan started as Music Organizer's `docs/roadmap/0.2-visualizer.md` earlier the same day.

- **The project:** a Swift package with three parts. The `ParticleAccelerator` library holds everything. The stand-alone app (`scripts/build_app.sh` → `build/Particle Accelerator.app`) is a first window listing the planned visuals. `pa-bench` measures a Mac's graphics card.
- **The plan:** `docs/PLAN.md` (roadmap, the picture routine, why Metal and not Unreal), `docs/VISUALS.md` (six cards), `docs/OUTPUT.md` (quality tiers, output options, measurements), `docs/INTEGRATION.md` (how Music Organizer will add it).
- **Measured on the iMac:** 300,000 particles at 2560×1440 in 4.8 ms per frame, so High quality at 60 fps.
- **Safety:** the secret check, hooks and CI are copied from Music Organizer. The check also refuses anything under `references/`, where the pictures the visuals are modelled on are kept on the owner's Mac.

### Phase 1, session 1: hearing a song file

2026-10-03. The app now plays a song file and shows what it hears. Session 2 adds the other three sources (the Mac's own sound, a microphone, a host app's player).

- **The listener** (`MusicListener`): plays a song file, with play, pause, seek and mute. Mute silences the speakers while the visuals still hear the song.
- **The analyser:** about 86 times a second it measures the last 2,048 samples and gives:
  - the 64 spectrum bars
  - the six bands
  - the loudness
  - auto-gain: each of these is measured against its own last ten seconds
- **Beats:** each kick as it lands, the tempo, and a steady count of beats that stays in step with the kicks and carries on when the drums drop out.
- **The signal chain:** source, range, curve, fade, for single levels (`LiveSignal`) and for the whole spectrum (`LiveSpectrum`). It can be saved and read back.
- **The sound check** (`SoundCheckView`): plain bars, band meters, a beat light and the tempo, with the song's controls. It stops drawing when its window can't be seen.
- **The app:** a song arrives by File → Open, by a drop on the window, or by "Open With" or the Dock icon. Space plays and pauses, and ⇧⌘M mutes. `--muted` starts it muted.
- **Tests:** 53 at first, on sound generated as they run. One plays a generated file through the real audio engine, muted, and checks that what the analyser hears matches the file sample for sample.

**Measured on the iMac (2026-10-03):**

- AVAudioEngine's own tap delivers sound only every tenth of a second, however small a buffer is asked for. That's too jerky to draw from.
- A Core Audio render notify delivers every 512 samples (11.6 ms), on the audio thread.
- The analyser takes 0.012 ms a frame at 60 fps (worst 0.08 ms).
- The sound check window uses 15–21% of one processor core while it draws, and 0.3% when minimised.
- **Tempo on real songs:** on the owner's sample song, "Do I Wanna Know?" by Arctic Monkeys (85 BPM), it reads 84–86 for 99% of the song. Of ten songs tried:
  - four have a published tempo, and all four match
  - three more hold one steady tempo
  - three wander between related tempos (see the limits below)

**Changes from the plan, and why:**

- **Where the sound is copied.** The plan didn't say. A render notify sits on a switched-off equaliser between the player and the mixer. That point is before the volume, so mute works, and it's at the file's own sample rate.
- **A small C target, `AtomicIntegers`.** The lock-free ring needs atomic numbers. Swift's own need macOS 15, and this project supports macOS 14. It's a few lines of the C standard library, not an outside package.
- **The analyser works in fixed steps of 512 samples, not once a frame.** Each frame works through the steps that have arrived. The beat tracker needs evenly spaced measurements, and this way a song gives the same readings at any frame rate.
- **Auto-gain's ranges.** A band or the loudness reads 0 at 20 decibels below its recent peak, and a bar at 40. A first try at 30 and 48 left the loudness pinned at full on a real song and the bars a solid block. A band is never turned up by more than 30 decibels against the whole sound, so an empty band doesn't show its hiss.
- **The spectrum isn't one of `SoundSource`'s cases.** A control driven by the spectrum gets 64 values, not one, so it has its own type (`LiveSpectrum`) with the same range, curve and fade.
- **Beats, tuned on real music.** Three things were added after the first try:
  - A beat must be at least half as strong as the strongest of the last few seconds. Bass notes between the kicks were being counted.
  - The tempo is measured from all 64 bars equally. The first try let the snare drown out the kick, and found half the tempo.
  - A settled tempo is kept through passages with no clear rhythm. It's replaced only by one heard clearly, and forgotten after ten seconds of silence. Without that, it jumped to double in the sample song's choruses.
- **Mute** wasn't in the plan. The owner asked for it, so checks can be run without sound.
- **Delaying the signals by the output's latency** moves to session 2, with the sources that need it most.

**Known limits:**

- **Half and double tempo.** A rhythm that repeats every beat also repeats every two, so 75 and 150 both fit. It picks the one nearer 125, between 60 and 180. Three of the ten songs wandered between related tempos (75 ↔ 150, 75 ↔ 112). Knowing a song ahead (phase 12) is the real fix.
- **A song with no kick drum** gives no beat pulses. The tempo and the steady count can still work.
- **A file with more than two channels** is heard through its first two.

**Frameworks:** this uses AudioToolbox, the part of Core Audio where the audio-unit functions live, and Swift's own Observation. The owner agreed the same day: AudioToolbox and MediaToolbox (for session 2) are now named in `CLAUDE.md` rule 2, and another of Apple's frameworks may be added when the work needs it.

**The made-up test song** (added the same day, at the owner's suggestion). `TestSong` builds 40 seconds of a dance beat from numbers, so every fact about it is known: 124 beats a minute, 82 kicks and the moment each lands, the bass notes, the loudest sample.

- Six tests listen to it and check the listener against those facts. That makes 59 tests.
- `scripts/make_test_song.sh` writes the same song to `build/Test Song 124.wav` for trying in the app.
- Checked in the app, muted: it reads 124 BPM.

### Phase 1, session 2: the other three sources, and timing

2026-10-03. The listener now hears all four sources, and keeps the picture in time with what's heard. That finishes phase 1.

- **This Mac's sound** (`listenToThisMac()`): whatever any app is playing, through a Core Audio process tap (macOS 14.2 and later). It only listens: nothing is muted or changed.
- **A microphone** (`listenToMicrophone()`): the input chosen in System Settings, followed if it changes.
- **A host app's player** (`listen(to:)`): a listening tap on whatever the `AVPlayer` plays now and next. The host's own sound settings for the item are kept, and put back when listening stops.
- **Timing:** each source knows how far ahead of the speakers it hears the sound, and the analyser only measures what has been heard.
  - A song file and the Mac's sound wait for the output's delay, as Core Audio reports it.
  - A player's tap is read by the player's own clock.
  - A microphone needs no wait.
  - `timingOffset` moves the picture later or earlier by up to half a second, for whatever is left.
- **The sound check** now shows what it's listening to, each band's real loudness in decibels, a timing control, and a note when something needs saying.
- **The app** has a Listen menu: Song File, This Mac's Sound (⌘1), Microphone (⌘2), Stop Listening (⌘.), and "Song File, the Way a Host App Plays It", which plays the file in a player of the app's own as a joined composition and hands that player to the listener. `--as-host` does the same for files opened at launch.
- **Tests:** 83. The player source is tested with a real `AVPlayer` turned down to nothing.

**Checked in the app on the iMac (2026-10-03):**

- **The host's way:** the made-up song as a joined composition, silent, read 124 BPM.
- **This Mac's sound:** heard the music the owner was playing, found its tempo, and showed its loudness.
- **The microphone:** heard the room through the Mac's own microphone, at about −64 decibels.
- **The permission with this ad-hoc-signed app:** macOS asks again after every rebuild. The owner was asked to allow about four times in the session, across two builds and two sources. A rebuild changes an ad-hoc signature, so macOS treats the rebuilt app as a new one. Signing with a lasting certificate would stop that; it isn't set up. (This entry first said the permission survived a rebuild. That was wrong: the prompts couldn't be seen from Claude's side, and the owner had allowed each one.)

**Measured (2026-10-03):**

- **A player's tap** is handed sound in blocks of 2,260 samples (47 ms), a steady 0.46 seconds before the speakers play it. What it's handed matches the file sample for sample, through a joined composition too.
- **A muted player:** with `isMuted`, the tap is handed real sound for about four seconds and then silence for as long as the player stays muted. With `volume = 0` it's handed real sound throughout.
- **Handing over a player that's already playing** makes it stop for about half a second while it sets its sound up again. Handed over before the item starts, nothing is heard.
- **The output's delay:** the owner's Bluetooth headphones report 195 ms (8,079 samples of delay and a 512-sample buffer, at 44,100 a second). The iMac's own speakers weren't the output during this session, so their figure is still to be read.

**Changes from the plan, and why:**

- **The tap's listening device contains only the tap.** Apple's sample code also puts the output device in it. Left out, the device has no microphone and no speakers of its own, so a headset's microphone can never be opened by accident and nothing can be played through it.
- **A Bluetooth headset is never used as the microphone.** Listening to one makes macOS switch it to call quality, which spoils the music the person is hearing (the owner's Mac had exactly this set up). The Mac's own microphone is used instead, with a note saying so. On a Mac with no microphone of its own, it's refused with the reason.
- **The microphone and the tap are read with Core Audio directly**, not AVAudioEngine, whose tap only delivers every tenth of a second.
- **The ring holds about six seconds, not one and a half.** A player's tap runs half a second ahead, so the ring has to keep more than the analyser looks at.
- **The ring is kept when a player sets its sound up again** (after a stall or a seek), so the analyser doesn't forget the tempo.
- **Sound too faint to be music has no beats and no tempo.** A quiet room through the microphone "found" a tempo in its hiss.

**Known limits:**

- **HLS and live streams** in a host's player can't be heard: macOS keeps their sound out of reach. `problem` says so.
- **A player muted with `isMuted`** goes quiet to the visuals after about four seconds. That's how macOS mutes.
- **Which microphone** follows System Settings. There's no chooser in the app yet.
- **The joined composition used for checking has a sound track only.** No picture track was made for it.
- **Not checked:**
  - refusing the permission prompts (the sound check shows a hint after four seconds of silence, and the microphone gives a plain error)
  - unplugging or changing the output while listening to the Mac's sound
  - a player playing faster or slower than normal

**A lesson about tests that play in real time.** All the tests start together, and for the first five or six seconds the ones that measure long stretches of sound keep every worker thread busy. Until they finish, macOS can't deliver timers or a player's callbacks: a 20 ms wait was seen to last six seconds, on the main thread's own timer too. A test that plays three seconds of sound then misses all of it. So each real-time test calls `waitForAQuietMoment()` first, and waits with `pause(seconds:)` instead of `Task.sleep`.

### Decisions after phase 1

2026-10-03.

- **Menus show a visual by its number only**, such as "Visualizer 3" (the owner's choice, for now). `VisualInfo.title` changed to match; `name` is still there for the docs.
- **The flashing limit is on by default, and a setting turns it off** (the owner's choice). `CLAUDE.md` rule 8 now says so. It's built with the stage in phase 2.

### Phase 2, session 1: the stage, and Visualizer 3 (Particle Wave)

2026-10-03. The first real visual is on screen, moving to the music. It's a first version: the owner hasn't watched it and given notes yet, so it isn't marked built.

- **The stage** (`Stage/`):
  - The visual is drawn into a floating-point picture at the quality tier's size, so light can be far brighter than white.
  - Glow is made from five smaller and smaller copies of the picture, added back together.
  - Finishing tones the picture to the screen, keeping colours saturated, with a vignette and fine grain that hides banding.
  - A display link of the view's own tells it when to draw. It stops when the window can't be seen, and drops to 20 frames a second after three seconds of silence.
  - Setting up (compiling shaders, making the sparks) happens away from the main thread.
- **Shaders** are Metal source in Swift files, compiled when the stage starts. A test compiles them all, and another asks Metal where it put each uniform and checks that against Swift.
- **A camera** with perspective that never stands still: a slow drift, a gentle roll, a slow breath, and a small punch on each beat. Sparks nearer or further than the line go slightly soft.
- **The frame-time counter:** frames a second, the graphics card's time for a frame (average and slowest), and the processor's time. View → Frame Time shows it.
- **Quality tiers** Low, Medium, High and Ultra, as in `OUTPUT.md`. More sparks make a finer picture, not a brighter one. Auto picks High, or Medium on a laptop's low-power graphics; it doesn't adapt yet.
- **Visualizer 3:**
  - The graphics card moves every spark each frame.
  - The spectrum is shaped into separate mountains across the whole width.
  - The line brightens with the loudness, and each kick sends a ripple along it from the bass end.
- **`AcceleratorView(listener:settings:)`** and **`AcceleratorSettings`** are the public way to show a visual. The app shows the visual by default; View → Sound Check (⌘D) swaps to the bars. The app saves its settings in its own preferences.
- **Tests:** 109.

**Measured on the iMac (2026-10-03), release build, each tier at its full size:**

| Tier | Sparks | Picture | Graphics card per frame |
|---|---|---|---|
| Low | 75,000 | 1280×720 | 0.7 ms |
| Medium | 150,000 | 1920×1080 | 1.6 ms |
| High | 300,000 | 2560×1440 | 3.9 ms (slowest 6.1) |
| Ultra | 1,000,000 | 3840×2160 | 26.2 ms |

- **High holds 60 fps** with room to spare (a frame allows 16.7 ms). Ultra doesn't on this Mac, as expected.
- **In the app:** 60 fps and 1.9 ms a frame at High in an 1800×1040 window, with the sample song playing muted.
- **Processor:** about 4% of one core while showing, 0.3% when minimised.
- **Flashing:** across two and a half minutes of the sample song, the whole picture's brightness never moved by more than 2.1% of white within a third of a second. A flash is a swing of 10% or more, so this visual doesn't flash.

**Changes from the plan, and why:**

- **The spectrum isn't drawn as it stands.** A real song's spectrum is broadly full, and as it stands it made one wide flat band, not the separate peaks in the reference. Each part of the spectrum is now measured against its own recent loudest moment, on a plain loudness scale, and each peak is spread into a triangle.
- **The view runs a display link of its own.** MTKView's built-in timer ran but never asked for a frame when the app was opened with a song.
- **The screen's drawable is kept at the picture's size** and the screen scales it up, rather than drawing a full 5K frame.
- **Brighter than white (EDR)** waits for phase 4, where the roadmap has it. The picture is drawn in floating point already.

**Still to do in phase 2:**

- **The owner's notes on Visualizer 3**, and tuning until they're happy. Then it's marked built.
- **Auto quality that adapts** while it plays.
- **The flashing limit itself.** The setting exists and is on, but there's nothing behind it yet. Visualizer 3 doesn't need it (measured above); a visual that flashes will.
- **Fog.** The camera has a setting for it that no visual uses yet.

### Phase 2, session 2: Visualizer 3 after the owner's first notes

2026-10-03. The owner watched the first version with a song or two. Their notes:

- In a busy passage "everything is just mushed together". With a slow beat it was fine.
- The sound check gives each section (sub, kick and so on) its own colour, sorted along a line. The visual had the line and the mountains but mixed the colours, "so it doesn't actually display anything". They asked for the visual to be separated into colours.
- The sparks were slow to return to the line, so when the next beat came the two blended.

What changed:

- **One colour for each band** (`Band.colour`): orange, pink, violet, blue, cyan and green, from the bass up. Each band's section of Visualizer 3 is that colour: its sparks, its reflection and its piece of the line. Before, every part of the spectrum was pink low down and blue high up.
- **The sound check uses the same six colours** for its bars and meters, so it works as a key to the visual. Its bars are now coloured by the band they belong to; they were a smooth run from blue to pink.
- **Hits stand above held sound.** A sound that holds steady sinks to 55% of its height, and one that has just jumped up by 8 decibels or more stands at its full height. In a busy passage everything is loud all the time, and this is what lets the beats show in it.
- **Sharper peaks.** A pitch 5 decibels quieter than the loudest nearby stands half as tall (it was 6), and each peak's triangle reaches two and a half bars to each side (it was three and a half).
- **Quick up and quick down.** A hit's sparks are most of the way up within a twentieth of a second, and down to a fifth of their height three tenths of a second after the sound stops. In the first version, getting down that far took a full second.
- **Each section of the line brightens with its own band.** It used to follow the loudness of the whole song.
- Fewer sparks float clear of the peaks (3%, was 5.5%), and more of each peak's sparks sit near its top.
- **Tests:** 114. New ones cover the bands' colours, each section's colour in the finished picture, and a kick every half second leaping every time and settling before the next.

**Measured on the iMac (2026-10-03), release build, each tier at its full size:**

| Tier | Graphics card per frame |
|---|---|
| Low | 0.7 ms |
| Medium | 1.5 ms |
| High | 3.6 ms (slowest 8.3) |
| Ultra | 22.2 ms |

- **In the app:** 60 fps and 3.2 ms a frame (slowest 3.9) at High in a 2546×1448 picture, with the sample song playing muted. About 7% of one processor core.
- **The busiest eight seconds of two songs,** before and after. "How full" is the mountains' average height; "how much it moves" is how far each bar's height swings in time, against its own average.

| | How full, before | after | How much it moves, before | after |
|---|---|---|---|---|
| The sample song's last chorus | 0.40 | 0.28 | 0.40 | 0.67 |
| A busy electronic song's drop | 0.35 | 0.25 | 0.51 | 0.83 |

- **Flashing:** across two and a half minutes of the sample song, the whole picture's brightness never moved by more than 7.2% of white within a third of a second (it was 2.1% in the first version). A flash is a swing of 10% or more, so this is still under it, but closer. The flashing limit isn't built yet, and this is a reason to build it soon.

**Still to do in phase 2:** the owner's notes on this second version (then Visualizer 3 is marked built), Auto quality that adapts, the flashing limit, fog.

### Phase 8 begun early: the controls panel, and the sound check under the visual

2026-10-03. After the second version of Visualizer 3 the owner asked for two things:

- **"An actual visualizer builder":** an app where they can change things themselves (speed, peaks, smoothness, colours, preferences), so the two of us can settle a look together, and which helps with future visuals. Whatever is made there has to go into Music Organizer "without any issue".
- **Both ⌘D displays on one screen,** without switching back and forth.

What was added:

- **The controls panel** (`AcceleratorControls`; View → Controls, ⌘E). For Visualizer 3 it has 23 sliders under five headings (Peaks, Movement, Sparks, Line, Picture) and a colour for each of the six bands.
  - A change shows at the next frame and is kept with the settings.
  - Each control has an arrow back to the visual's own setting, and Reset All puts everything back.
  - Resting the pointer on a control says what it does.
- **Each visual lists its controls** (`ParticleWave.controls`): a name, a heading, a range, the visual's own setting and a sentence of help. The panel is drawn from the list, so a new visual gets its panel by listing its controls.
- **A person's changes are part of `AcceleratorSettings`** (`controls`, a `ControlValues`). Only what was changed is saved, so the rest follows the visual's own settings when those get better.
- **It all lives in the library, not the app,** which is what lets it reach Music Organizer: the same settings give the same picture in any app, and the panel can be shown there too.
- **The sound check now shows under the visual** (⌘D), not in its place. Its bars run in the same order and the same colours as the visual's sections, and take any colour picked in the panel.
- The app remembers whether the sound check and the controls were showing.
- Settings saved before today still open, with the quality and the rest as they were.
- **Tests:** 131. New ones cover a person's changes (kept, limited to their range, saved and read back), every control's details, and the picture changing with a control and with a picked colour. One draws the picture with every control at each end of its range.

**Measured on the iMac (2026-10-03),** High quality, the sample song, a 2676×1182 picture:

| What's showing | Frames a second | One processor core |
|---|---|---|
| The visual alone | 60 | about 7% |
| The visual over the sound check, as the sound check was first built | 44–50 | about 100% |
| The same, with the sound check drawing only shapes for each frame | 60 | 17–27% |
| The visual, the sound check and the controls panel | 60 | 25–50% |

**Changes from the plan, and why:**

- **Phase 8 was started before phases 3 to 7,** because the owner asked for it. What's built is the plain controls and colours. Still to come in phase 8: presets (save, name, share as a file), choosing which part of the music drives each control, and building blocks a person can add.
- **The sound check was rebuilt inside.** It laid its whole view out afresh for every frame, which was fine alone but took a whole processor core beside the visual and cost the visual a quarter of its frames. Its bars, meters and beat light are now shapes drawn in one pass, and its words change four times a second. `CLAUDE.md` has this as a rule for any view that redraws every frame.
- **The bands' colours reach the shaders each frame.** They were written into the shader when it was compiled, which a colour picker can't change. The visual's own numbers for the shaders grew from 8 to 32.
- **"Fall" is one control for two things:** how long a peak takes to sink and how fast its sparks drop. They had separate settings of 0.10 and 0.11 seconds; both are now 0.11.
- **No draggable dividers** between the visual, the sound check and the controls: their sizes are fixed for now.

**Known limits:**

- **The stage draws on the app's main thread,** so heavy work elsewhere in the window can cost it a frame. The rate dips for a moment when Reset All redraws every control. `CLAUDE.md` rule 6 says nothing should make the drawing wait on the main thread, and this falls short of it. Drawing on a thread of its own is the fix, and is still to do.
- **Dragging a slider wasn't checked by hand.** The sliders were moved by clicking on their tracks, and the picture followed. The owner's own dragging is the real check.
- **No presets yet:** there's one set of changes, kept with the app's settings.

