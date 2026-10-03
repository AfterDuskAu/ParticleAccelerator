#!/bin/bash
# Write the made-up test song to build/ as "Test Song 124.wav", for trying in the app.
#
#     scripts/make_test_song.sh
#
# Everything about the song is known exactly, because it's built from numbers: 124
# beats a minute, 40 seconds, a kick on every beat (82 of them). The tests listen to
# the same song (Tests/ParticleAcceleratorTests/TestSong.swift). To check the app with
# it without any sound:
#
#     open -a "build/Particle Accelerator.app" "build/Test Song 124.wav" --args --muted
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SONG="$REPO/build/Test Song 124.wav"
mkdir -p "$REPO/build"

swiftc -O "$REPO/Tests/ParticleAcceleratorTests/TestSong.swift" \
    "$REPO/scripts/make_test_song/main.swift" -o "$REPO/build/make-test-song"
# Only ever this script's own output.
rm -f "$SONG"
"$REPO/build/make-test-song" "$SONG"
