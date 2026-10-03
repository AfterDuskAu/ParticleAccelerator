# Changelog

## 0.1.0 (in progress): setting up

2026-10-03. The owner asked for a music visualizer as a project of its own, named Particle Accelerator, to be added to Music Organizer when it's done. The plan started as Music Organizer's `docs/roadmap/0.2-visualizer.md` earlier the same day.

- **The project:** a Swift package with three parts. The `ParticleAccelerator` library holds everything. The stand-alone app (`scripts/build_app.sh` → `build/Particle Accelerator.app`) is a first window listing the planned visuals. `pa-bench` measures a Mac's graphics card.
- **The plan:** `docs/PLAN.md` (roadmap, the picture routine, why Metal and not Unreal), `docs/VISUALS.md` (six cards), `docs/OUTPUT.md` (quality tiers, output options, measurements), `docs/INTEGRATION.md` (how Music Organizer will add it).
- **Measured on the iMac:** 300,000 particles at 2560×1440 in 4.8 ms per frame, so High quality at 60 fps.
- **Safety:** the secret check, hooks and CI are copied from Music Organizer. The check also refuses anything under `references/`, where the pictures the visuals are modelled on are kept on the owner's Mac.
