# The visuals

One card per visual. Numbers are given in the order the reference pictures arrived and are never reused; the building order is separate (`PLAN.md`). Difficulty runs from ★ (easy) to ★★★★★.

The pictures are references only. Each visual is drawn by code in the same style, and nothing from a picture (logos, artwork) is copied in. They're kept in `references/` as `visualizer-<N>-<name>.<ext>`, on the owner's Mac only, because they belong to other people.

| # | Name | How close | Difficulty | State |
|---|---|---|---|---|
| 1 | Ring & Ink | very close | ★★ | planned |
| 2 | Iron Maw | a stylised version | ★★★★★ | planned |
| 3 | Particle Wave | close in shape; the colours are ours | ★★ | second version built 2026-10-03, after the owner's first notes; waiting for their notes on it |
| 4 | Tendrils | close in motion; the colours are ours | ★★★★ | base design built 2026-10-04; the owner tuned it and set its standard the same day |
| 5 | Fountain | very close | ★ | base design built 2026-10-04; the owner tuned it and locked it in the same day, then tuned it again that afternoon and set a new standard |
| 6 | Starburst | a firework from the centre, at the owner's direction | ★★★ | second base design built 2026-10-04, after the owner's notes on the first; for the owner to tune |
| 7 | Corona | ours: Visualizer 4 laid out by band | ★★★★ | base design built 2026-10-04, at the owner's request; the owner tuned it and set its standard the same day |
| 8 | Jets | ours: Visualizer 5 laid out by band | ★★ | base design built 2026-10-04, at the owner's request; the owner tuned it and set its standard the same day |

**A base design** is a first version with every setting on a slider (View → Controls), built so the owner can shape it themselves. It isn't marked built until they're happy with it.

**Base, standard and lock** (the owner, 2026-10-04). Every control has two settings of the visual's own:

- **Its base:** the plain first setting the visual was designed with. **Reset All** goes back to it.
- **Its standard:** what the visual shows until someone changes it. **Reset to Standard** goes back to it, and **Set Standard** makes the settings as they are now the standard.
- A visual whose standard the owner has settled has it written into the library (`Tendrils.standard`, `Fountain.standard`, `Corona.standard`, `Jets.standard`), so it looks the same in any app. A standard set with the button is kept in that person's settings.
- **Lock** keeps a visual as it is: nothing in its panel can be moved until it's unlocked. Visualizer 5 starts locked.
- Each visual has its own colours, and they're part of its standard.

**Visualizers 7 and 8 have no reference picture.** They're copies of 4 and 5 that the owner asked for, laid out so that every part of the picture belongs to particular bars of the spectrum. Their cards say what they are in place of a picture.

**In every visual with particles:**

- **Each band has its colour.** Each visual has its own six, which start as the same six everywhere. The owner can pick others or have them change by themselves (below).
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
- **The owner's standard (2026-10-04):** slow strands (speed 0.47×) that curl and turn a great deal (curl 4×, turning 3.82×) round a bigger hole (1.77×). Trails so short the strands show as beads (0.05 s). A camera that moves a lot (4×). Colours that change by themselves, a new set every 4.68 s. The owner's note on it: "it feels kind of chaotic", which is what Visualizer 7 is for.

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
- **The owner's standard (2026-10-04, afternoon):** a tall spray (height 1.24×, spread 1.56×, gravity 3×) of small, very bright, twinkling sparks (size 0.65×, brightness 4×, twinkle 1.93×) that last as long as they can (life 2.5×), hardly white at all (white heat 3%), with streaks (1.39×) and bigger bursts on the kick (2.16×). Hardly any glow on the floor (0.17×). A camera that drifts as at its base (1.10×) and barely jumps on the beat (0.21×), a darker picture with less glow, and colours that stay as they are. Its panel starts locked.
  - This replaces the standard the owner locked in that morning (a wide spray of fewer sparks, spread 3.5× and amount 0.43×, a camera that moved a lot, and colours that changed by themselves). They unlocked it, tuned it again and pressed Set Standard, then asked for it to be the library's.

## 6. Starburst ★★★

*Reference: a still of particle streams bursting outward in 3D (sent in chat on 2026-10-03; never saved in `references/`).*

- **In the picture:** lavender-white streams of sparks shoot outward from a centre in 3D, each led by a bright head. Near sparks are big and blurred, far ones small and sharp.
- **How close:** no longer close to the picture's streams, at the owner's direction (below). The centre, the depth and the blur are the picture's.
- **Needs:** a 3D camera with depth of field (blur by distance), and sparks that are thrown and fly.
- **The owner's notes on the first base design (2026-10-04):** "instead of it being short burst. id like it more if it was continiously moving outward. like a firwork. no direct line straight out. just firing off from the center. and once the moment has passed for it, it fades but still moved outward." The first design fired streams on each kick: lines of sparks behind a bright head, which flew out, stopped where they'd reached, and faded there.
- **As built (second base design, 2026-10-04):**
  - **Sparks fire from the centre all the time,** in every direction. A trickle in silence, most of them when it's loud.
  - **Each kick throws a shell** of them at once, a little faster than the rest, so it runs out through them.
  - **No lines.** Every spark has a heading of its own, so no two follow each other out.
  - **They never stop.** The air slows a spark towards a steady drift outward, and it sinks a little, as a firework's sparks do. It's at its brightest for the first fifth of its flight and fades over the rest, still flying.
  - **Each spark is a pale shade of a band's colour** (Whiteness sets how pale; at 100% it's the picture's own lavender-white). The stronger a band is as a spark fires, the more of the sparks are its colour and the faster they leave.
  - The centre glows with the loudness and pulses on each kick. Sparks flying towards the camera go out of focus into soft discs.
- **Its controls:** Burst (amount, speed, kick burst, life, slowing, droop, turning), Sparks (size, brightness, bright for, twinkle, whiteness, blur, streaks), Centre glow, Movement, Picture, Colours.

## 7. Corona ★★★★

*No reference picture: Visualizer 4, laid out by band (the owner, 2026-10-04).*

- **Why:** the owner asked for a copy of Visualizer 4 "a lot more responsive to their specific bars. it feels kind of chaotic." In Visualizer 4 every strand flows to the whole song and the curl mixes the bands together, so nothing in the picture can be traced to a part of the music.
- **In it:** the same dark hole, with the same curling strands pouring out of it. But the ring of strands has a shape, and the shape is the music's.
- **With the music:**
  - **The bands take their places round the hole,** the same on the left as on the right: sub at the bottom, then kick, low mids, mids and vocals, to air at the top. Each band has an equal share of the ring, and its own bars are spread across its share.
  - **A strand reaches as far as its own bars are loud,** and brightens with them. Its tip is brightest, so the tips trace the music's shape.
  - **It does that at once.** A strand's sparks are already flowing along its whole length, unlit. Only as much of it as the music calls for is lit, so a strand is out within a tenth of a second of a hit and gone half a second after it stops. In Visualizer 4 the sparks have to travel, which takes seconds.
  - **A fresh hit reaches further than a sound that holds,** so beats show in a busy song. This is the same measure of the spectrum that Visualizer 3's peaks stand on.
  - The bass pushes every strand's sparks out faster and swells the hole on each kick. The highs make the specks sparkle.
- **The owner's standard (2026-10-04):** four times as many strands (4×), finer (thickness 0.76×) and brighter (1.68×), reaching far (reach 1.71×) with bright tips (3.71×). Small, tight curls (curl 1.84×, curl size 0.31×), a small hole (0.81×) and a ring that turns (1.06×). A strong push from the bass (3.30×) and on the beat (1.60×). Bars that move with their neighbours (width 8 bars), show more of a held sound (86%) and let go quickly (fall 0.052 s). A camera that moves a lot (4×), and colours that stay as they are.
  - It began as the owner's Visualizer 4 in everything the two share, with Curl and Turning back at their base, because they're what mixes one band's strands in with the next's. The owner turned both up again when they tuned it.
- **Its controls:** Reach (reach, tips), Response (quieter pitches, held sound, width, fall), Flow, Strands, Movement, Picture, Colours.

## 8. Jets ★★

*No reference picture: Visualizer 5, laid out by band (the owner, 2026-10-04).*

- **Why:** the same request as Visualizer 7. In Visualizer 5 every band's sparks are thrown together from one mouth to the loudness of the whole song.
- **In it:** a row of jets across the floor, each a narrow fountain of the same sparks, leaning out a little from the middle like a fan.
- **With the music:**
  - **Each band has jets of its own,** in its colour, in the sound check's order: sub on the left to air on the right. Three for each band to start with, and each follows its own part of its band's bars.
  - **A jet stands as tall as its own bars are loud,** throws more sparks the louder they are, and glows at its mouth with them. Nothing else moves it.
  - **The sparks rise and fall quickly:** a full jet's are at the top in under half a second. So a jet is up within a beat and down before the next. Quickness sets this.
  - **A fresh hit stands taller than a sound that holds,** as in Visualizer 7.
  - On each beat the kick's jets jump higher. The highs make the sparks twinkle.
- **The owner's standard (2026-10-04):** eight jets for each band, in a narrow row (row width 0.60×) fanned wide (fan 4.21×, spread 3.05×). Many small, twinkling sparks (amount 3.74×, size 0.61×, twinkle 2×) that rise and fall slowly (quickness 0.51×), last as long as they can (life 2.5×) and leave long streaks (4×). No glow on the floor. A camera that hardly moves (0.24×) or jumps (0.17×), a darker picture with less glow, and colours that change by themselves, a new set every 4.68 s.
  - It began as the owner's Visualizer 5 of that morning in everything the two share, with the jets at their base: three for each band, rising and falling quickly.
- **Its controls:** Jets (jets for each band, height, quickness, row width, spread, fan, amount, kick burst, life), Response (quieter pitches, held sound, width, fall), Sparks, Floor glow, Movement, Picture, Colours.
