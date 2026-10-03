#!/bin/bash
# Build the stand-alone app and put it in build/ as "Particle Accelerator.app".
#
#     scripts/build_app.sh          build it
#     scripts/build_app.sh --open   build it and open it
#
# Signed "ad hoc", for this Mac only (sharing it with other Macs needs signing and
# notarising, not set up yet).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO/build/Particle Accelerator.app"
VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' \
    "$REPO/Sources/ParticleAccelerator/Visuals.swift")"

echo "Building…"
swift build --package-path "$REPO" -c release --product ParticleAcceleratorApp
BINARY="$(swift build --package-path "$REPO" -c release --show-bin-path)/ParticleAcceleratorApp"

# Only ever this script's own output folder.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/ParticleAccelerator"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Particle Accelerator</string>
    <key>CFBundleDisplayName</key><string>Particle Accelerator</string>
    <key>CFBundleIdentifier</key><string>org.particleaccelerator.app</string>
    <key>CFBundleExecutable</key><string>ParticleAccelerator</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built: $APP"
if [ "${1:-}" = "--open" ]; then
    open "$APP"
fi
