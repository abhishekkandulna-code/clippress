#!/usr/bin/env bash
# Builds ClipPress.app and packages it as build/ClipPress-<version>.dmg, a disk image with
# the app next to an Applications shortcut so users can drag it in to install.
# Run on a Mac:  ./scripts/make-dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."

bash scripts/build-app.sh

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
DMG="build/ClipPress-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto build/ClipPress.app "$STAGE/ClipPress.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "ClipPress" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov "$DMG" >/dev/null

hdiutil verify "$DMG" >/dev/null

echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
