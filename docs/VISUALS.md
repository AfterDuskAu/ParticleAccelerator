# The visuals

One card per visual. Numbers are given in the order the reference pictures arrived and are never reused; the building order is separate (`PLAN.md`). Difficulty runs from ★ (easy) to ★★★★★.

The pictures are references only. Each visual is drawn by code in the same style, and nothing from a picture (logos, artwork) is copied in. They're kept in `references/` as `visualizer-<N>-<name>.<ext>`, on the owner's Mac only, because they belong to other people.

| # | Name | How close | Difficulty | State |
|---|---|---|---|---|
| 1 | Ring & Ink | very close | ★★ | planned |
| 2 | Iron Maw | a stylised version | ★★★★★ | planned |
| 3 | Particle Wave | close in shape; the colours are ours | ★★ | second version built 2026-10-03, after the owner's first notes; waiting for their notes on it |
| 4 | Tendrils | close in motion; the colours are ours | ★★★★ | base design built 2026-10-04; for the owner to tune |
| 5 | Fountain | very close | ★ | base design built 2026-10-04; for the owner to tune |
| 6 | Starburst | close | ★★★ | base design built 2026-10-04, from the card alone (the picture still isn't in `references/`); for the owner to tune |

**A base design** is a first version with every setting on a slider (View → Controls), built so the owner can shape it themselves. It isn't marked built until they're happy with it.

**In every visual with particles:**

- **Each band has its colour,** the same six everywhere, and the owner can pick their own or have them change by themselves (below).
- **Sparks are drawn the way a camera sees them** (2026-10-04, after the owner asked for "more realistic, more high def"): a hot core with a soft skirt, drawn out into a short streak when it's moving fast, and an even disc when it's out of focus.
- **Colours that change by themselves** (2026-10-04): switched on, the six colours drift slowly from one made-up set to the next and never settle. The sets are six hues spread round the colour wheel, so neighbouring bands always stay apart.

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
- **Its controls** (View → Controls, since 2026-10-03), each with its own setting to go back to:
  - **Peaks:** height, width, how much the quieter pitches show, how tall a held sound stands.
  - **Movement:** rise, fall, drift, camera movement, beat punch.
  - **Sparks:** size, brightness, twinkle, fullness, floating sparks, reflection.
  - **Line:** thickness, brightness, haze, kick ripple, tremble.
  - **Picture:** glow, brightness, dark corners.
  - **Colours:** one for each band.
  - Added 2026-10-04: **Bars** (how many bars of the spectrum the peaks are made from, 8 to 64) and **Streaks**.

## 4. Tendrils ★★★★

*Reference: a still of curling light strands around a dark centre.*

- **In it:** a dark round hole in the middle. Thousands of fine, curling strands of blue light, some pink, pour outward, with specks of light along them.
- **With the music:** the strands flow outward and curl like smoke in a slow current. Bass pushes them out faster and swells the hole, highs send sparkles running along them, and the whole field turns slowly. The song's cover can sit in the hole.
- **How close:** close in motion. The picture's hair-fine detail comes from a slow offline render; ours comes near it with trails, and closer still on faster Macs, which can afford more strands.
- **Needs:** a flow field ("curl noise") and trails (each frame fades a little instead of being cleared).
- **As built (base design, 2026-10-04):**
  - **A strand is a file of sparks** following each other out from one place on the hole's rim. Each frame the last picture is dimmed a little and the sparks drawn on top, so each leaves a short trail and the file joins into a line.
  - **The current** that bends them is a few broad waves crossing each other, slowly changing. It bends the strands without bunching them, the way smoke moves.
  - **Each strand is a band's colour.** The bands take turns round the hole, three sprays each, and a spray surges outward and brightens with its band. The picture's own blue and pink can be had by picking those colours.
  - **The bass** pushes every strand out faster, and the hole swells on each kick.
  - Some strands are bright and most are faint, so the brighter ones stand out as separate lines. About one spark in thirty is a bright speck that twinkles with the highs.
  - The camera moves less than in the other visuals: the trails stay where the picture was, so a moving camera smears them.
  - The cover in the hole waits for the visuals that use artwork.
- **Its controls:** Flow (speed, bass push, curl, curl size, turning, hole size), Strands (how many, trail, thickness, brightness, specks, twinkle), Movement, Picture, Colours.

## 5. Fountain ★

*Reference: a still of a spark fountain.*

- **In it:** a white-hot point at the bottom, with sparks of every colour spraying up in a widening cone and a soft glow on the floor.
- **With the music:** the spray's height and amount follow loudness, and each kick throws a burst. Highs make the sparks twinkle, and the glow on the floor pulses.
- **How close:** very close.
- **Needs:** a particle emitter.
- **As built (base design, 2026-10-04):**
  - Sparks wait at the mouth and are thrown up: a trickle in silence, most of them when it's loud, and a burst on each kick. The louder the song, the faster they leave, so the higher the spray.
  - Each leaves white-hot and takes its colour on the way up. Gravity and the air slow it, and it fades before it lands.
  - **Each spark is a band's colour.** The stronger a band is as a spark is thrown, the more of the sparks are its colour, so the spray's colours show what's playing.
  - A glow lies on the floor and stands at the mouth, and both pulse with the loudness and the kick.
- **Its controls:** Spray (height, spread, amount, kick burst, gravity, life), Sparks (size, brightness, twinkle, white heat, streaks), Floor glow, Movement, Picture, Colours.

## 6. Starburst ★★★

*Reference: a still of particle streams bursting outward in 3D (sent in chat on 2026-10-03; to be saved as `references/visualizer-6-starburst`).*

- **In it:** lavender-white streams of sparks shoot outward from a centre in 3D, each led by a bright head. Near sparks are big and blurred, far ones small and sharp.
- **With the music:** kicks fire new bursts, and loudness sets their speed and how many streams there are. The camera drifts slowly into the burst, and near sparks go out of focus.
- **How close:** close.
- **Needs:** a 3D camera with depth of field (blur by distance), and bursts.
- **As built (base design, 2026-10-04):**
  - Each kick fires a burst, and the last four are in the air together. A stream is a head with a trail of sparks following it out, fast at first and slowing.
  - **Each stream belongs to a band** and is a pale shade of its colour (Whiteness sets how pale; at 100% it's the picture's own lavender-white). The stronger the band, the further its streams reach.
  - The louder the song, the faster the streams and the more of them fire.
  - Between kicks a thin field of sparks drifts outward, faster when it's loud, so the picture is never empty.
  - Sparks flying towards the camera go out of focus into soft discs.
  - Nothing is kept from frame to frame: where a spark is follows from its number and how long ago its kick landed.
- **Its controls:** Burst (streams, reach, speed, trail, spread, drift between kicks, turning), Sparks (size, brightness, twinkle, whiteness, heads, blur, streaks), Movement, Picture, Colours.
