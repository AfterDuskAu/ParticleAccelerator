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

That's the plan for version 1.0.0. **What works today:**

```swift
let listener = MusicListener()
listener.listen(to: player)                              // once, when the player is made
AcceleratorView(listener: listener, settings: settings)  // the visual
AcceleratorControls(settings: $settings)                 // the panel that changes it while it plays
SoundCheckView(listener: listener, controls: settings.controls)  // plain bars and meters
```

`settings` is an `AcceleratorSettings`: which visual (only 3 so far), the quality, whether to show the frame time, and the person's own changes to the visual (`controls`). The artwork comes with Visualizer 1.

**A look made in Particle Accelerator comes across as it is.** There's nothing to export or convert:

- Each visual's own settings are in the library, so they arrive with the package.
- A person's changes (the sliders and colours of `AcceleratorControls`) are in `AcceleratorSettings.controls`, which is `Codable`. A host that's handed the same settings shows the same picture.
- Only what the person changed is saved. Everything else follows the visual's own settings, so a host gets improvements to those without losing the person's changes.
- The controls panel itself is in the library, so the host can offer the same sliders.

Three things a host should know about its player:

- **Hand it over once, early, and leave it handed over.** Handing over a player that's already playing makes the song stop for about half a second while macOS sets its sound up again. Handed over before a song starts, nothing is heard, and the listener follows the player from song to song by itself.
- **Turn it down with `volume = 0`, not `isMuted`,** if the visuals should carry on. macOS stops handing a muted player's sound to the listener after about four seconds.
- **HLS and live streams can't be heard.** macOS keeps their sound out of reach. `listener.problem` says so in plain English.

Optional extras for a host that wants its own menus:

- `Visuals.all`: every visual's number and name, for a picker. Its `title` is what menus show: the number only for now ("Visualizer 3").
- `AcceleratorControls(settings: $settings)`: the library's own controls panel, ready to drop into the host's Settings or beside the visual. It works today for a visual's controls and colours; choosing the visual and the quality in it comes later.

## What the library promises a host

- **It never changes the sound.** It adds a listening tap to the player's current item, and removes it when listening stops. The host's playback, volume and seeking are untouched, and any sound settings the host put on the item (an `audioMix`) are kept and put back.
- **It writes no files and uses no network.**
- **It costs nothing when hidden.** Drawing stops when the view isn't on screen, and listening stops when it's gone.
- **It keeps out of the host's way, and the host out of its.** Frames are drawn on a thread of the library's own. A busy host window doesn't cost the visual frames, and the visual takes nothing from the host's main thread but a few settings changes.
- **It needs only macOS 14 and Apple's frameworks.** No other packages come with it.
- **No surprises:** a change to anything `public` gets a new version number and a note at the bottom of this file. Hosts pin a version (`from: "1.0.0"`), so an update never arrives by itself.

## Music Organizer specifically

- Its Local Visualizer page gets **Visualizer** beside Cover and Video. The player there is the app's single `AVPlayer` (`Player.screen`), and the artwork is the playing song's cover.
- The listener should be given that player when the app starts, not when the Visualizer is opened, so opening it mid-song doesn't make the song hiccup.
- If Music Organizer's mute button sets `isMuted`, the visuals go still a few seconds after muting.
- That fits Music Organizer's rules: the app never writes inside the library, and the visualizer writes nothing at all.
- Music Organizer's repo is public, and its CI must be able to fetch this package, so this repo is public too (since 2026-10-03).

## Changes to the public API

The API is still a plan until version 1.0.0, and these may change before then.

- **0.1.0, 2026-10-03, added:**
  - `MusicListener`: plays a song file and listens to it (`play(songFile:)`, `pause()`, `resume()`, `seek(to:)`, `stop()`, `isMuted`, `songTitle`, `isPlaying`, `duration`, `currentTime`).
  - `SoundCheckView(listener:)`: plain bars, meters and a beat light showing what the listener hears.
- **0.1.0, 2026-10-03, added in phase 1's second session:**
  - `MusicListener.listen(to:)` for a host's `AVPlayer`, `listenToThisMac()` and `listenToMicrophone()`.
  - `MusicListener.source` (a `MusicListener.Source`), `sourceName` and `problem`.
  - `MusicListener.timingOffset`: shows the visuals up to half a second later or earlier.
  - A host that uses `listenToThisMac()` or `listenToMicrophone()` needs `NSAudioCaptureUsageDescription` or `NSMicrophoneUsageDescription` in its Info.plist. Listening to its own player needs neither.
- **0.1.0, 2026-10-03, changed:** `VisualInfo.title` is now the number only ("Visualizer 3"), not the number and name ("3 · Particle Wave"). `name` is unchanged.
- **0.1.0, 2026-10-03, added in phase 2:**
  - `AcceleratorView(listener:settings:)`: the visual.
  - `AcceleratorSettings` (`visual`, `quality`, `limitsFlashing`, `showsFrameTime`) and `Quality` (`auto`, `low`, `medium`, `high`, `ultra`). `limitsFlashing` has nothing behind it yet.
- **0.1.0, 2026-10-03, added with the controls panel:**
  - `AcceleratorControls(settings:)`: a slider for each of the chosen visual's controls and a colour for each band.
  - `AcceleratorSettings.controls`, a `ControlValues`: the person's own changes (`isEmpty`, `resetAll()`). What's inside it is the library's business; a host only keeps it.
  - `SoundCheckView(listener:controls:)`: the same view, with the bands in the person's colours. `SoundCheckView(listener:)` still works.
  - Settings saved by an older version still open: whatever they lack starts as it would in new settings.
