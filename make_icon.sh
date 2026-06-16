#!/bin/bash
# Render the app icon and package it as AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ Rendering icon…"
swift Icon/make_icon.swift

ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"; mkdir "$ICONSET"

gen() { sips -z "$2" "$2" icon_1024.png --out "$ICONSET/$1" >/dev/null; }
gen icon_16x16.png        16
gen icon_16x16@2x.png     32
gen icon_32x32.png        32
gen icon_32x32@2x.png     64
gen icon_128x128.png      128
gen icon_128x128@2x.png   256
gen icon_256x256.png      256
gen icon_256x256@2x.png   512
gen icon_512x512.png      512
gen icon_512x512@2x.png   1024

iconutil -c icns "$ICONSET" -o AppIcon.icns
rm -rf "$ICONSET" icon_1024.png
echo "✅ AppIcon.icns"
