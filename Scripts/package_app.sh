#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
BUILD_DIR="$PROJECT_DIR/.build/app-package"
ICONSET_DIR="$BUILD_DIR/Presence.iconset"
APP_DIR="$PROJECT_DIR/dist/Presence.app"
ZIP_PATH="$PROJECT_DIR/dist/Presence.zip"

cd "$PROJECT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$BUILD_DIR" "$APP_DIR"
rm -f "$ZIP_PATH"
mkdir -p "$ICONSET_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

swift "$PROJECT_DIR/Scripts/generate_icon.swift" "$BUILD_DIR/icon_1024.png"

for SPEC in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"
do
    SIZE="${SPEC%% *}"
    NAME="${SPEC#* }"
    sips -z "$SIZE" "$SIZE" "$BUILD_DIR/icon_1024.png" \
        --out "$ICONSET_DIR/$NAME" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/Presence.icns"
cp "$BIN_DIR/Presence" "$APP_DIR/Contents/MacOS/Presence"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

xattr -cr "$APP_DIR"
codesign --force --deep --sign - \
    --entitlements "$PROJECT_DIR/Resources/Presence.entitlements" \
    "$APP_DIR"
xattr -cr "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

ditto -c -k --norsrc --noextattr --keepParent "$APP_DIR" "$ZIP_PATH"

VERIFY_DIR="$(mktemp -d /tmp/presence-package.XXXXXX)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k --norsrc --noextattr "$ZIP_PATH" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/Presence.app"

echo "$ZIP_PATH"
