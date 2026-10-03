# CLAUDE.md: Particle Accelerator

Standing rules for every Claude Code session in this project. Read this file and `docs/PLAN.md` before writing code; read `docs/VISUALS.md`, `docs/OUTPUT.md` and `docs/INTEGRATION.md` when the work touches them. If a prompt conflicts with this file, **this file wins**: stop and say so instead of guessing.

## What this project is

A Mac app and library that turn music into moving visuals: particles, light, ink and 3D shapes, driven live by the real sound. Each visual is made from a reference picture the owner sends (Visualizer 1, 2, …). It started on 2026-10-03 as a spin-off of the owner's Music Organizer app, and is built on its own first. When it's ready it goes into Music Organizer as a package (`docs/INTEGRATION.md`).

The owner builds with Claude Code and is not a professional programmer. Prefer boring, obvious code with good error messages over clever code. The development machine is a 2019 Intel iMac (AMD Radeon Pro 570X, 5K screen), but the project must also make full use of much faster Macs (`docs/OUTPUT.md`).

## Non-negotiable rules

1. **The library comes first, and the app is a thin shell over it.** Everything lives in the `ParticleAccelerator` library: hearing the music, the stage, the visuals, the settings. Anything the app can do, a host app can do through the library's public API. The app adds only windows, menus and file pickers.
2. **It stands alone.**
   - It uses Apple's own frameworks only: AVFoundation, Accelerate, Metal, MetalKit, Core Audio, SwiftUI and AppKit. Ask before adding anything else.
   - It never imports, links or knows about Music Organizer.
3. **The public API is a promise.** Anything `public` is something Music Organizer may use. Changing or removing it means a version bump, a note in `docs/INTEGRATION.md` and an entry in `docs/CHANGELOG.md`. Keep the public surface small; everything else is `internal`.
4. **It listens and never changes the sound.**
   - The library never alters the audio it hears.
   - It never writes files and never uses the network.
   - The app writes only its own settings, plus video exports and preset files the person asks for, to a place they chose. It never overwrites a file: a name that's taken gets ` (2)`, ` (3)`.
5. **It scales.** Every visual has quality controls (particle count, drawing size, effects). It must hold 60 fps on the iMac at High quality, measured with the frame-time counter, and grow to use a Mac Studio's power (`docs/OUTPUT.md`). Auto quality picks a tier and adapts.
6. **Real-time safety.**
   - Nothing on the audio thread allocates memory, takes a lock, calls Swift concurrency or logs.
   - Nothing makes the drawing wait on the main thread.
   - Drawing stops when the view is hidden.
7. **Shaders are Metal source kept as text in Swift files, compiled when the stage starts.** `swift build` doesn't compile `.metal` files (checked 2026-10-03), and the app bundle has no resource folder. A test compiles every shader.
8. **Flashing is limited.** Whole-screen flashes happen at most 3 times a second, on by default, for people sensitive to flashing light.
9. **The reference pictures belong to other people.** They live in `references/`, which is git-ignored, and `scripts/check_secrets.py` refuses them. Never commit them, and never copy a picture's logos or artwork into a visual: the visuals are drawn by code in a similar style.

## Architecture

- `Sources/ParticleAccelerator/`: the library (`import ParticleAccelerator`). Planned parts:
  - `Audio/`: audio sources (a file, the Mac's own sound, a microphone, a host's `AVPlayer`), the analyser and beats, and the four-step signal chain
  - `Stage/`: the Metal renderer, particles, the camera, glow, quality tiers and Auto
  - `Visuals/`: one file per visual
  - `Settings/`: `Codable` settings and presets
- `Sources/AtomicIntegers/`: a few lines of C, so the audio thread and the analyser can share a count without a lock (Swift's own atomics need macOS 15).
- `Sources/ParticleAcceleratorApp/`: the stand-alone app. `scripts/build_app.sh` builds `build/Particle Accelerator.app`.
- `Sources/PABench/`: `pa-bench`, which measures a Mac's graphics card and suggests a tier (`swift run -c release pa-bench`).
- `Tests/ParticleAcceleratorTests/`: Swift Testing.

## Conventions

- Swift 6 tools in Swift 5 language mode, macOS 14 or later. Type annotations on anything public.
- Names say what things are, in plain English. Comments say why, not what.
- Errors shown to a person are plain English, e.g. "This Mac's sound can't be heard until you allow it in System Settings → Privacy & Security → Screen & System Audio Recording." Never a raw error code.
- Numbers about speed are measured, not guessed. Record them in `docs/OUTPUT.md` with the Mac and the date.

## Secrets (assume this repository is public)

- Never commit keys, passwords, tokens, personal email addresses, or paths and details from the owner's Mac (`/Users/...`). Anything committed stays public even after a later commit deletes it.
- Commits use the owner's private GitHub noreply address, set in this repo's own git config (the global one is personal), never a personal email.
- Commits and pushes go through the `.githooks/` secret check (`scripts/check_secrets.py`, copied from Music Organizer). It's switched on per clone with `git config core.hooksPath .githooks`. Never bypass it with `--no-verify`. If it flags something harmless, fix the line or end it with a `secrets-ok` comment, and say so.

## Testing

- `swift build` and `swift test` must pass before a step is declared done. Run them, don't assume.
- Sound for tests is generated while the test runs: sine waves at known pitches, click tracks at known tempos, silence, noise. No audio files are committed.
- Tests that need the graphics card skip, saying why, when the computer has none (some CI machines). They must run and pass on the iMac.
- Tests never use the network, and never use the owner's music or the real microphone or system sound.

## Working with the owner

- Commit when a step's work is done and checked; there's no need to ask first. The owner usually pushes.
- Playing a song makes sound on the owner's Mac, so stop it straight after a check.
- Don't take over the screen (full screen, moving windows) while the owner is using the Mac. Say first what's about to be shown and for how long.
- New visuals follow the routine in `docs/PLAN.md`: a card first, the owner's OK, then build.

## Definition of done for any step

1. The step's checks in `docs/PLAN.md` pass, run for real.
2. `swift build` and `swift test` pass locally and in CI.
3. `docs/CHANGELOG.md` has a short entry: what was added, and any change from the plan and why.
4. For anything visible, it was looked at in the running app, and its frame time on the iMac is recorded.
5. No public API changed without rule 3's notes.
