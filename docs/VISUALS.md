# The visuals

One card per visual. Numbers are given in the order the reference pictures arrived and are never reused; the building order is separate (`PLAN.md`). Difficulty runs from ★ (easy) to ★★★★★.

The pictures are references only. Each visual is drawn by code in the same style, and nothing from a picture (logos, artwork) is copied in. They're kept in `references/` as `visualizer-<N>-<name>.<ext>`, on the owner's Mac only, because they belong to other people.

| # | Name | How close | Difficulty | State |
|---|---|---|---|---|
| 1 | Ring & Ink | very close | ★★ | planned |
| 2 | Iron Maw | a stylised version | ★★★★★ | planned |
| 3 | Particle Wave | close in shape; the colours are ours | ★★ | second version built 2026-10-03, after the owner's first notes; waiting for their notes on it |
| 4 | Tendrils | close in motion | ★★★★ | planned |
| 5 | Fountain | very close | ★ | planned |
| 6 | Starburst | close | ★★★ | planned; picture still to be saved in `references/` |

## 1. Ring & Ink ★★

*Reference: a frame of a song's visualizer video on YouTube.*

- **In it:** a logo in a white circle, with a thin white ring around it and a second ring slightly off-centre. Red-and-black ink or smoke, mirrored left and right, with faint stars and dark red edges.
- **With the music:** the ring swells on each kick, and its outline ripples with the spectrum. The second ring lags behind the first. The ink swirls slowly, faster and brighter when the song is loud. The colours come from the song's cover.
- **How close:** very close. The song's own cover goes in the circle; with no cover (the Mac's sound, a microphone) the circle glows in the visual's colours.
- **Needs:** a background shader, the ring, the cover in the middle, colours taken from the cover.

## 2. Iron Maw ★★★★★

*Reference: a frame of Vizibeat's Iron Maw demo (vizibeat.com/demos/iron-maw), with the demo page's description.*

- **In it:** a dark 3D room, a glowing red ring like an eclipse, rings of metal spikes around it, stage lights.
- **With the music:** the camera orbits slowly, rolls and shakes on the kick. Spikes punch outward on the beat and the hit ripples to their neighbours. Lights fire in turn, one step per beat, and the inner ring twists.
- **How close:** a stylised version. The demo uses hand-made 3D models and Unreal Engine's lighting, while ours is built from simple shapes with glow. The movement can match; the richness of the look can't.
- **Needs:** 3D shapes with lighting, a beat counter (one step per beat), camera behaviours.

## 3. Particle Wave ★★

*Reference: a still of a particle waveform.*

- **In the picture:** a glowing orange-pink line across the middle. Tens of thousands of blue, violet and pink sparks form peaks above it, with a dimmer reflection below.
- **With the music:**
  - The peaks are the spectrum, bass on the left and highs on the right.
  - Each of the six bands has a section of its own, in its own colour: its sparks, its reflection and its piece of the line. From the bass: orange, pink, violet, blue, cyan, green.
  - Sparks leap up their peaks on a hit and drop straight back, so one beat is over before the next lands.
  - Each section of the line brightens with its own band, and a kick sends a ripple along the line.
- **How close:** close in shape. The colours are ours, not the picture's (see the owner's notes below).
- **Needs:** particles on the graphics card, glow, the spectrum. Built first, because it shows straight away whether the sound is being read correctly.
- **The owner's notes on the first version (2026-10-03):** "everything is just mushed together" in a busy passage; the colours were mixed, so the picture showed nothing about which part of the music was doing what; and the sparks were slow to come back to the line, so one beat ran into the next. They asked for the visual to be separated into colours the way the sound check is.
- **As built (second version, 2026-10-03):**
  - **One colour for each band,** the same six the sound check uses for its bars and meters. In the first version every part of the spectrum was pink low down and blue high up.
  - **The peaks aren't the raw spectrum.** Each part of it is measured against its own recent loudest moment, so there are separate mountains right across and not one flat band. A pitch 5 decibels quieter than its neighbour stands half as tall.
  - **Hits stand above held sound.** A sound that holds steady sinks to just over half its height, and one that has just jumped up stands at its full height. So in a busy passage the beats still show.
  - **Quick up and quick down.** A hit's sparks are most of the way up within a twentieth of a second, and down to a fifth of their height three tenths of a second after the sound stops. In the first version, getting down that far took a full second.
  - A third of the sparks are the reflection, and a few float clear of the peaks.
  - One spark in eight is bright enough to be seen by itself; the rest make a mist.
  - Each kick's ripple runs along the line from the bass end.

## 4. Tendrils ★★★★

*Reference: a still of curling light strands around a dark centre.*

- **In it:** a dark round hole in the middle. Thousands of fine, curling strands of blue light, some pink, pour outward, with specks of light along them.
- **With the music:** the strands flow outward and curl like smoke in a slow current. Bass pushes them out faster and swells the hole, highs send sparkles running along them, and the whole field turns slowly. The song's cover can sit in the hole.
- **How close:** close in motion. The picture's hair-fine detail comes from a slow offline render; ours comes near it with trails, and closer still on faster Macs, which can afford more strands.
- **Needs:** a flow field ("curl noise") and trails (each frame fades a little instead of being cleared).

## 5. Fountain ★

*Reference: a still of a spark fountain.*

- **In it:** a white-hot point at the bottom, with sparks of every colour spraying up in a widening cone and a soft glow on the floor.
- **With the music:** the spray's height and amount follow loudness, and each kick throws a burst. Highs make the sparks twinkle, and the glow on the floor pulses.
- **How close:** very close.
- **Needs:** a particle emitter.

## 6. Starburst ★★★

*Reference: a still of particle streams bursting outward in 3D (sent in chat on 2026-10-03; to be saved as `references/visualizer-6-starburst`).*

- **In it:** lavender-white streams of sparks shoot outward from a centre in 3D, each led by a bright head. Near sparks are big and blurred, far ones small and sharp.
- **With the music:** kicks fire new bursts, and loudness sets their speed and how many streams there are. The camera drifts slowly into the burst, and near sparks go out of focus.
- **How close:** close.
- **Needs:** a 3D camera with depth of field (blur by distance), and bursts.
