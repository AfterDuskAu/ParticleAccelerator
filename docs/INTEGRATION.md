# Adding Particle Accelerator to another app

How a host app, first of all Music Organizer, adds the visuals. **This is the plan for the API, written before the code** so the library is built to fit it. Phase 9 of `PLAN.md` makes it real and tags version 1.0.0; until then, names may change.

## The whole job, for a host

**1. Add the package** to the host's `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/AfterDuskAu/ParticleAccelerator", from: "1.0.0"),
],
// and in the app target:
dependencies: [.product(name: "ParticleAccelerator", package: "ParticleAccelerator")],
```

**2. Show the visuals** where the host wants them:

```swift
import ParticleAccelerator

AcceleratorView(
    source: .player(player),   // the host's AVPlayer; follows whatever it plays next
    artwork: coverImage,       // optional: for visuals with the cover in them
    settings: $settings        // AcceleratorSettings: which visual, quality, timing…
)
```

**3. Keep the settings:** `AcceleratorSettings` is `Codable`, so the host saves it wherever it keeps its own settings. The library never saves anything itself.

That's all. Optional extras for a host that wants its own menus:

- `Visuals.all`: every visual's number and name, for a picker.
- `AcceleratorControls(settings: $settings)`: the library's own settings panel, ready to drop into the host's Settings.

## What the library promises a host

- **It never changes the sound.** It adds a listening tap to the player's current item, and removes it when the view goes away. The host's playback, volume and seeking are untouched.
- **It writes no files and uses no network.**
- **It costs nothing when hidden.** Drawing stops when the view isn't on screen, and listening stops when it's gone.
- **It needs only macOS 14 and Apple's frameworks.** No other packages come with it.
- **No surprises:** a change to anything `public` gets a new version number and a note at the bottom of this file. Hosts pin a version (`from: "1.0.0"`), so an update never arrives by itself.

## Music Organizer specifically

- Its Local Visualizer page gets **Visualizer** beside Cover and Video. The player there is the app's single `AVPlayer` (`Player.screen`), and the artwork is the playing song's cover.
- That fits Music Organizer's rules: the app never writes inside the library, and the visualizer writes nothing at all.
- Music Organizer's repo is public, and its CI must be able to fetch this package, so this repo is public too (since 2026-10-03).

## Changes to the public API

None yet. The API is still a plan.
