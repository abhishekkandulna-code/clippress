#!/usr/bin/env bash
# Builds build/ClipPress.app from the Swift package as a universal app (Apple Silicon + Intel).
# Run on a Mac with Xcode or the Command Line Tools installed:  ./scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

# Build each architecture on its own, then merge them with lipo. (A single multi-arch
# `swift build` needs full Xcode; this way the Command Line Tools are enough.)
BINS=()
for ARCH in arm64 x86_64; do
    echo "Building for $ARCH..."
    swift build -c release --arch "$ARCH"
    BINS+=("$(swift build -c release --arch "$ARCH" --show-bin-path)/ClipPress")
done

APP="build/ClipPress.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"

lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/ClipPress"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Fonts/*.ttf Resources/Fonts/OFL.txt "$APP/Contents/Resources/Fonts/"

# Ad-hoc signature so Gatekeeper lets it run on this Mac.
codesign --force --sign - "$APP"

echo "Built $APP ($(du -sh "$APP" | cut -f1), $(lipo -archs "$APP/Contents/MacOS/ClipPress"))"
