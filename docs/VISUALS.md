# The visuals

One card per visual. Numbers are given in the order the reference pictures arrived and are never reused; the building order is separate (`PLAN.md`). Difficulty runs from ★ (easy) to ★★★★★.

The pictures are references only. Each visual is drawn by code in the same style, and nothing from a picture (logos, artwork) is copied in. They're kept in `references/` as `visualizer-<N>-<name>.<ext>`, on the owner's Mac only, because they belong to other people.

| # | Name | How close | Difficulty | State |
|---|---|---|---|---|
| 1 | Ring & Ink | very close | ★★ | planned |
| 2 | Iron Maw | a stylised version | ★★★★★ | planned |
| 3 | Particle Wave | very close | ★★ | planned (built first) |
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

- **In it:** a glowing orange-pink line across the middle. Tens of thousands of blue, violet and pink sparks form peaks above it, with a dimmer reflection below.
- **With the music:** the peaks are the spectrum, bass on the left and highs on the right. Sparks ride their peaks with a little drift, then fall and fade. The line brightens and flickers with loudness, and a kick sends a ripple along it.
- **How close:** very close.
- **Needs:** particles on the graphics card, glow, the spectrum. Built first, because it shows straight away whether the sound is being read correctly.

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
