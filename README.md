# Particle Accelerator

Visuals that move with the music, for the Mac. Particles, light, ink and 3D shapes are driven live by the real sound of a song file, whatever the Mac is playing, or a microphone. It works on an older Intel iMac and scales up to a Mac Studio on a 4K or 6K screen.

**Status:** just started (version 0.1.0). The app opens a window listing the visuals on their way, and nothing plays yet. See [`docs/PLAN.md`](docs/PLAN.md).

## The visuals

| # | Name | State |
|---|---|---|
| 1 | Ring & Ink | planned |
| 2 | Iron Maw | planned |
| 3 | Particle Wave | planned (first) |
| 4 | Tendrils | planned |
| 5 | Fountain | planned |
| 6 | Starburst | planned |

What each one looks like and how it moves: [`docs/VISUALS.md`](docs/VISUALS.md).

## Build and run

Needs macOS 14 or later and Xcode's command-line tools.

```bash
scripts/build_app.sh --open
```

Measure what this Mac's graphics card can draw, and see the quality it suggests:

```bash
swift run -c release pa-bench
```

Run the tests:

```bash
swift test
```

## In another app

Particle Accelerator is a Swift package. Another Mac app adds it with one line in `Package.swift` and shows it with one view. See [`docs/INTEGRATION.md`](docs/INTEGRATION.md). Music Organizer is the first.

## Docs

- [`docs/PLAN.md`](docs/PLAN.md): the roadmap, and why it's built on Apple's Metal
- [`docs/VISUALS.md`](docs/VISUALS.md): one card per visual
- [`docs/OUTPUT.md`](docs/OUTPUT.md): quality tiers, output options, and measurements
- [`docs/INTEGRATION.md`](docs/INTEGRATION.md): adding it to another app
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md)
