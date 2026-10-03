# Particle Accelerator

Visuals that move with the music, for the Mac. Particles, light, ink and 3D shapes are driven live by the real sound of a song file, whatever the Mac is playing, or a microphone. It works on an older Intel iMac and scales up to a Mac Studio on a 4K or 6K screen.

**Status:** early (version 0.1.0). Four visuals are on screen: Visualizer 3 (Particle Wave) in its second version, and base designs of Visualizers 4, 5 and 6 for the owner to shape. It moves to a song file, to whatever the Mac is playing, or to a microphone. A controls panel (View → Controls) changes its peaks, movement, sparks, line and colours while it plays. See [`docs/PLAN.md`](docs/PLAN.md).

## The visuals

| # | Name | State |
|---|---|---|
| 1 | Ring & Ink | planned |
| 2 | Iron Maw | planned |
| 3 | Particle Wave | second version built |
| 4 | Tendrils | base design built |
| 5 | Fountain | base design built |
| 6 | Starburst | base design built |

What each one looks like and how it moves: [`docs/VISUALS.md`](docs/VISUALS.md).

## Build and run

Needs macOS 14 or later and Xcode's command-line tools.

```bash
scripts/build_app.sh --open
```

Then choose what to listen to:

- **A song file:** drop it on the window, or choose File → Open… Space plays and pauses, and ⇧⌘M mutes the speakers while the bars keep moving.
- **Whatever the Mac is playing** (Spotify, a browser): Listen → This Mac's Sound. It needs macOS 14.2 or later, and macOS asks for permission the first time.
- **A microphone:** Listen → Microphone. It uses the input chosen in System Settings → Sound.

In the View menu: Quality (Auto, Low, Medium, High, Ultra), Frame Time (how long each frame takes), and Sound Check (plain bars and meters in place of the visual).

To start it muted (for checking the picture without any sound):

```bash
open "build/Particle Accelerator.app" --args --muted
```

Measure what this Mac's graphics card can draw, and see the quality it suggests:

```bash
swift run -c release pa-bench
```

Run the tests:

```bash
swift test
```

Make a test song whose tempo is known exactly (124 beats a minute), for trying in the app:

```bash
scripts/make_test_song.sh
```

## In another app

Particle Accelerator is a Swift package. Another Mac app adds it with one line in `Package.swift` and shows it with one view. See [`docs/INTEGRATION.md`](docs/INTEGRATION.md). Music Organizer is the first.

## Docs

- [`docs/PLAN.md`](docs/PLAN.md): the roadmap, and why it's built on Apple's Metal
- [`docs/VISUALS.md`](docs/VISUALS.md): one card per visual
- [`docs/OUTPUT.md`](docs/OUTPUT.md): quality tiers, output options, and measurements
- [`docs/INTEGRATION.md`](docs/INTEGRATION.md): adding it to another app
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md)
