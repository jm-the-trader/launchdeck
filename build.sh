#!/bin/bash
# Compile the SwiftUI sources into a double-clickable LaunchDeck.app bundle.
set -euo pipefail
cd "$(dirname "$0")"

APP="LaunchDeck.app"
ARCH="$(uname -m)"
echo "▶ Building Launch Deck for ${ARCH}…"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Launch Deck</string>
  <key>CFBundleDisplayName</key><string>Launch Deck</string>
  <key>CFBundleIdentifier</key><string>com.michael.launchdeck</string>
  <key>CFBundleExecutable</key><string>LaunchDeck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

# Bundle the Dock icon if it's been generated (./make_icon.sh).
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "⚠️  AppIcon.icns not found — run ./make_icon.sh for a custom Dock icon."
fi

swiftc -O \
  -target "${ARCH}-apple-macos13.0" \
  -framework SwiftUI -framework AppKit \
  -o "$APP/Contents/MacOS/LaunchDeck" \
  Sources/*.swift

# Local build → ensure it isn't quarantined so Gatekeeper won't block it.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "✅ Built $APP"
echo "   Run it:        open $APP"
echo "   Install it:    cp -R $APP /Applications/"
