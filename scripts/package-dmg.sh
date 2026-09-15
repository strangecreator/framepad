#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d dist/Framepad.app ]; then
    bash scripts/build.sh
fi
staging="$(mktemp -d "$PWD/.build/dmg-stage.XXXXXX")"
ditto dist/Framepad.app "$staging/Framepad.app"
ln -s /Applications "$staging/Applications"
cp Resources/Install.txt "$staging/Start here.txt"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Framepad.app/Contents/Info.plist)"
dmg_path="dist/Framepad-${app_version}.dmg"
hdiutil create -volname Framepad -srcfolder "$staging" -ov -format UDZO -imagekey zlib-level=9 "$dmg_path"
hdiutil verify "$dmg_path"
shasum -a 256 "$dmg_path" > "${dmg_path}.sha256"
printf 'Installer built: %s\n' "$dmg_path"
