#!/bin/bash
# Builds TakoKey.app and TakoKey.dmg from TakoKey.swift in this folder.
# Needs only Xcode Command Line Tools:  xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

APP=build/dmg/TakoKey.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"

# 1. Compile. arm64 only: every M-series Mac runs it natively.
swiftc -O -swift-version 5 -target arm64-apple-macos13 \
    TakoKey.swift -o "$APP/Contents/MacOS/TakoKey"

# 2. App icon: icon.png -> AppIcon.icns with every size Finder asks for.
mkdir -p "$APP/Contents/Resources" build/AppIcon.iconset
for s in 16 32 128 256 512; do
    sips -z $s $s icon.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) icon.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# 3. The bundle's ID card. LSUIElement = menu-bar app, no Dock icon, no app switcher entry.
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>     <string>TakoKey</string>
    <key>CFBundleIconFile</key>       <string>AppIcon</string>
    <key>CFBundleIdentifier</key>     <string>io.github.bvpotapenko.takokey</string>
    <key>CFBundleName</key>           <string>TakoKey</string>
    <key>CFBundlePackageType</key>    <string>APPL</string>
    <key>LSMinimumSystemVersion</key> <string>13.0</string>
    <key>LSUIElement</key>            <true/>
</dict>
</plist>
PLIST

# 4. Ad-hoc signature ("-" = no certificate). Apple Silicon won't run unsigned code,
#    and signing the whole bundle seals the Info.plist to the binary.
codesign --force --sign - "$APP"

# 5. DMG = the app plus an /Applications shortcut to drag it onto.
ln -s /Applications build/dmg/Applications
hdiutil create -volname TakoKey -srcfolder build/dmg -ov -format UDZO TakoKey.dmg

echo "Built $(pwd)/TakoKey.dmg"
echo "Or install directly (removes the old copy first, so macOS doesn't kill the new one):"
echo "  pkill -x TakoKey; rm -rf /Applications/TakoKey.app && cp -R $APP /Applications/"
