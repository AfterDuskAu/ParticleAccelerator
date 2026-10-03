# Plan

**Status, 2026-10-03:** phase 1 is half done. The app plays a song file and shows what it hears: spectrum bars, six bands, loudness, a beat light and the tempo. No visual is built yet. Next is phase 1's second session: hearing the Mac's own sound, a microphone and a host app's player.

## What it is

Visuals that move with the music. The real sound is measured about 60 times a second, and it drives particles, light, colour and the camera. There are several visuals (`VISUALS.md`), each made from a reference picture, and more come as more pictures arrive. It runs as its own Mac app and, when ready, inside Music Organizer (`INTEGRATION.md`). It scales from the owner's 2019 iMac to a Mac Studio (`OUTPUT.md`).

The method comes from [Vizibeat](https://vizibeat.com/demos/iron-maw/): pick one part of the sound (the kick, say), clean it into a smooth signal, and send that signal to everything at once. Nothing is keyframed or tied to one song, so every song gets its own show.

## Why Apple's Metal, not Unreal Engine (decided 2026-10-03)

The owner asked whether to build it in Unreal Engine, the game engine Vizibeat runs in. Not for now:

- **The iMac can't run it properly.** Unreal 5.8 asks for an Apple Silicon Mac (M1 or M2 at least, M3 recommended) and 16 GB of memory ([Epic's Mac requirements](https://dev.epicgames.com/documentation/en-us/unreal-engine/macos-development-requirements-for-unreal-engine)).
- **Claude couldn't do the work well.** An Unreal project is mostly binary files, edited by clicking through Unreal's editor. Claude reads and writes text, so it can build, test and check Swift and Metal code from start to finish.
- **It wouldn't fit into Music Organizer.** An Unreal app is a separate program of several hundred megabytes; it can't live inside a SwiftUI window. This package plugs in with one line.
- **Metal is the same graphics card, used directly.** The measurements in `OUTPUT.md` show room for 300,000 particles at 60 fps on the iMac, and far more on Apple Silicon.

**What Unreal does better:** the richest 3D lighting, and a visual editor to tinker in. Iron Maw (visual 2) is the one that would look best there. **A door kept open:** phase 12's OSC output can send the beat and band signals to other programs, Unreal and Vizibeat included, on a future Apple Silicon Mac.

**The cost of Metal:** it's Mac-only. Music Organizer's Windows app (its 2.0) would need these visuals redrawn in another graphics system. The analysis, settings and presets carry over; the drawing code doesn't. That's far off, and choosing a cross-platform system now would cost speed and simplicity on the Mac.

## Where the sound comes from

All four feed the same analyser, so every visual works with every source.

1. **A song file**, dropped on the window or opened from the menu. Played by the app itself.
2. **Whatever the Mac is playing** (Spotify, a browser, Music Organizer). This uses Core Audio's process taps, in macOS 14.2 and later. macOS asks once for permission ("Screen & System Audio Recording"). How that permission behaves with an ad-hoc-signed app is checked in phase 1.
3. **A microphone or line input**, for a room, a turntable, a band.
4. **A host app's `AVPlayer`** (Music Organizer): a listening tap on the item it plays. It should work on files and progressive streams such as YouTube's, but not on HLS streams. Proven in phase 1 with a test player playing a YouTube-style joined composition.

## How the music drives a visual

Each visual has a few controls. Visual 5's, for example, are spray height, burst size and sparkle. Each control is fed through four steps:

1. **Source:** one part of the sound.
   - Sub (20–60 Hz), Kick (60–150 Hz), Low mids (150–500 Hz), Mids (500 Hz–2 kHz), Vocals and snare (2–6 kHz), Air (6–16 kHz).
   - Loudness, for the whole sound.
   - Beat, a pulse on each beat.
   - Spectrum, all 64 bars.
2. **Range:** the low and high points that are stretched to 0–1 (Vizibeat's *Normalize*).
3. **Curve:** straight, or steeper so only the strong hits show.
4. **Fade:** how fast it rises and how slowly it falls away (Vizibeat's *Tail*).

Every visual comes with good settings, and the controls editor (phase 8) lets the owner change them and save presets.

**How it works inside:**

- Samples go into a lock-free ring buffer; the audio thread never allocates memory or waits.
- Every 512 samples (about 86 times a second; each frame works through the steps that have arrived):
  - a 2,048-sample FFT (Accelerate's vDSP) with a Hann window
  - 64 bars on a log scale
  - the named bands
  - RMS loudness
- **Beats:** spectral flux in the kick band, against a moving threshold and against the strongest kicks of the last few seconds. The tempo comes from the onsets' autocorrelation, which gives a beat phase, so visuals can step in time and anticipate the next beat.
- **Auto-gain:** each band is measured against its own last 10 seconds or so, so a quiet verse and a big drop look different, and quiet and loud songs both move. A band reads 0 at 20 decibels below its recent peak, and a bar at 40.
- **Timing:** a tap hears the sound slightly before the speakers play it, so the signals are delayed by the output device's latency (from Core Audio). A ± setting covers the rest.

## The stage (what draws everything)

- **One Metal view at the chosen frame rate.** It stops when hidden, and idles slowly in silence.
- **The picture:**
  - drawn into a floating-point image
  - glow added
  - toned to the screen, with brighter-than-white highlights where the screen can show them
- **Particles live on the graphics card** (compute shaders), as many as the quality tier allows.
- **A 3D camera:**
  - perspective, depth of field and fog, so every visual has depth
  - never still: a slow drift, a gentle roll, a punch on the drop, made from small behaviours that never show an obvious loop
- **A frame-time counter**, so every visual's cost is known on every Mac.
- **The flashing limit** (`CLAUDE.md` rule 8).

## Roadmap

| Phase | What | What the owner sees | Size (sessions) |
|---|---|---|---|
| 0 | **Set up** (done 2026-10-03): the repo, rules, plan, secret checks, CI, a first app window, `pa-bench` | A window listing the visuals | done |
| 1 | **Hearing the music:** the four sources, the analyser, beats, the signal chain. Tests on generated tones and click tracks. Plain test bars and a beat light in the app. **Session 1 done 2026-10-03:** a song file, the analyser, beats, the signal chain, the sound check, mute. **Session 2:** the Mac's own sound, a microphone, a host's player, and timing. | Bars dancing to a song file (now), then to Spotify or a browser | 2 |
| 2 | **The stage and quality tiers, with Visual 3 (Particle Wave):** the drawing, glow, particles, camera, frame counter, Low to Ultra, Auto | The first real visual | 2–3 |
| 3 | **Visual 5 (Fountain)** | | 1 |
| 4 | **Output options:** window, full screen on any screen, an output screen, frame rate, drawing size, brighter than white | Visuals on a TV or second monitor | 1–2 |
| 5 | **Visual 1 (Ring & Ink)**, with the cover from a song file's own tags | | 1–2 |
| 6 | **Visual 6 (Starburst)** | | 1–2 |
| 7 | **Visual 4 (Tendrils)** | | 2 |
| 8 | **The controls editor and presets:** each control's source, range, curve and fade; save, name, reset, and share as a file | Vizibeat-style "what moves with what" | 2 |
| 9 | **Ready for Music Organizer:** the public API finished as in `INTEGRATION.md`, a test host that uses only that API, version 1.0.0 tagged. Then one session in Music Organizer to add it. | Visuals inside Music Organizer | 1 + 1 |
| 10 | **Recording a video** from a song file, at any size and frame rate (`OUTPUT.md`) | 4K videos, even from the iMac | 2 |
| 11 | **Visual 2 (Iron Maw)** | | 3–5 |
| 12 | **Later, if wanted:** knowing a song ahead (beats, sections, drops) so visuals build up before a drop; colours from the cover for every visual; OSC output to other programs; a MIDI controller; changing visuals at a song's section changes; more pictures | | |

**Why this order:**

- **Visual 3 comes first** because it shows the measured spectrum directly, so any problem hearing the music is obvious.
- **The visuals then run easiest to hardest**, each adding one new building block: the emitter, then the background shader, 3D depth, trails, and finally 3D shapes.
- **Music Organizer gets it after five visuals and the editor**, when there's a full set to use every day. The owner can move phase 9 earlier at any time.

**Rough total:** 20–28 sessions, plus the owner's time watching and giving notes.

**Not planned:** splitting a song into drums, bass and vocals (Vizibeat's "split the mix"). It needs an AI model that runs slowly on the Intel iMac, and a large new dependency.

## From a picture to a visual (the routine for every new picture)

1. **The owner sends a picture**, or several, in chat, with any wishes ("the line should jump with the kick").
2. **It is saved** as `references/visualizer-<N>-<name>.<ext>`, never committed.
3. **Claude adds a card** to `VISUALS.md`: what's in it, how it moves with the music, how close it can get, its difficulty, and what it needs that isn't built yet. It's also added to `Visuals.all` as not yet built.
4. **The owner OKs the card**, or changes it, and says where it goes in the building order.
5. **It is built and tried on three test songs:** a bass-heavy one, a calm acoustic one and a vocal pop one. (The owner's standing sample song is "Do I Wanna Know?" by Arctic Monkeys, 85 BPM.) Claude checks the frame time on the iMac at High and compares saved frames with the picture.
6. **The owner watches it** and gives notes, and it's tuned until they're happy.
7. **Its settings become its built-in preset.** It's marked built, with a changelog entry and a commit.

## Decisions waiting for the owner

1. ~~Public or private on GitHub?~~ **Public** (owner, 2026-10-03): github.com/AfterDuskAu/ParticleAccelerator.
2. **Names in menus:** "3 · Particle Wave" (number and name, as built) or numbers only?
3. **The flashing limit, on by default?** Suggested: yes.
4. **Two more of Apple's frameworks?** `CLAUDE.md` rule 2 names seven and says to ask before adding any other.
   - **AudioToolbox** is in use since phase 1: it's the part of Core Audio that holds the audio-unit functions, which is how the sound is copied for the analyser.
   - **MediaToolbox** is needed in phase 1's second session: the listening tap on a host app's `AVPlayer` is made with it, and there's no other way.
   - Suggested: add both to the rule.
