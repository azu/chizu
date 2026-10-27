#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
swift build -c release

app=dist/Chizu.app
mkdir -p "$app/Contents/MacOS"
cp Resources/Info.plist "$app/Contents/Info.plist"
version=$(bash scripts/version.sh)
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$version" "$app/Contents/Info.plist"
cp .build/release/chizu "$app/Contents/MacOS/chizu"
chmod 755 "$app/Contents/MacOS/chizu"

codesign --force --sign "${CHIZU_SIGNING_IDENTITY:--}" "$app"
codesign --verify --strict "$app"
printf 'Built %s\n' "$app"
