#!/usr/bin/env bash
# Build a release miniBrowser.app and install it to /Applications.
# Usage: ./scripts/build-app.sh           # build + install to /Applications
#        ./scripts/build-app.sh --no-install   # just build into dist/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
INSTALL=1
[[ "${1:-}" == "--no-install" ]] && INSTALL=0

echo "› Building release…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="$ROOT/dist/miniBrowser.app"
echo "› Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MiniBrowserApp" "$APP/Contents/MacOS/miniBrowser"
cp "$ROOT/scripts/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>miniBrowser</string>
  <key>CFBundleDisplayName</key><string>miniBrowser</string>
  <key>CFBundleIdentifier</key><string>dev.gum798.miniBrowser</string>
  <key>CFBundleExecutable</key><string>miniBrowser</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

echo "› Ad-hoc code signing"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"

if [[ "$INSTALL" == "1" ]]; then
  DEST="/Applications/miniBrowser.app"
  if cp -R "$APP" "/Applications/" 2>/dev/null || { rm -rf "$DEST" && cp -R "$APP" "/Applications/"; }; then
    # nudge LaunchServices/Dock to pick up the new icon
    touch "$DEST"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" 2>/dev/null || true
    echo "✓ Installed to $DEST"
    echo "  Launch from Spotlight/Launchpad, or: open -a miniBrowser"
  else
    echo "⚠ Could not write to /Applications. The app is at: $APP"
    echo "  Drag it into Applications yourself."
  fi
else
  echo "✓ Built at $APP (not installed)"
fi
