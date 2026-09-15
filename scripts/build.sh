#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${CONFIGURATION:-release}"
architectures="${ARCHITECTURES:-arm64 x86_64}"
mkdir -p dist .build/package
for architecture in $architectures; do
    swift build --disable-sandbox -c "$configuration" --triple "$architecture-apple-macosx14.0" --scratch-path ".build/$architecture"
done

app="dist/Framepad.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
executables=()
for architecture in $architectures; do
    executables+=(".build/$architecture/$architecture-apple-macosx/$configuration/Framepad")
done
lipo -create "${executables[@]}" -output "$app/Contents/MacOS/Framepad"
cp resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift .build/package/AppIcon.iconset
iconutil -c icns .build/package/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
chmod +x "$app/Contents/MacOS/Framepad"

identity="${SIGNING_IDENTITY:--}"
if [ "$identity" = "-" ]; then
    codesign --force --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --deep --strict --verbose=2 "$app"
printf 'App built: %s\n' "$app"
