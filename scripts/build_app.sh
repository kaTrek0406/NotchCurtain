#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME=NotchCurtain
BUNDLE_ID=io.github.katrek0406.NotchCurtain
TARGET=NotchCurtain
VERSION="$(cat "$ROOT/VERSION")"
APP="$ROOT/.build/$APP_NAME.app"
BIN="$ROOT/.build/release/$TARGET"
cd "$ROOT"
swift build -c release
"$ROOT/scripts/fetch_adapter.sh"
ADAPTER="$ROOT/.build/deps/mediaremote-adapter"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ADAPTER/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"
/usr/bin/ditto "$ADAPTER/build/MediaRemoteAdapter.framework" "$APP/Contents/Resources/MediaRemoteAdapter.framework"
codesign --force --deep --sign - "$APP/Contents/Resources/MediaRemoteAdapter.framework"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY.md" "$APP/Contents/Resources/"
cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
for LOCALE in en ru; do [[ ! -d "$ROOT/Sources/$TARGET/${LOCALE}.lproj" ]] || cp -R "$ROOT/Sources/$TARGET/${LOCALE}.lproj" "$APP/Contents/Resources/"; done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string><key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string><key>CFBundleDisplayName</key><string>$APP_NAME</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$VERSION</string><key>CFBundleShortVersionString</key><string>$VERSION</string><key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/><key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
printf 'Built: %s\n' "$APP"
