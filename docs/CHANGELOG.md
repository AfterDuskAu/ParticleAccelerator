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
- **The permission with this ad-hoc-signed app:** after the app was rebuilt (which changes its signature) the Mac's sound was heard again within a second and a half, with nothing lost. Whether macOS showed its prompt the first time couldn't be seen from here.

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
