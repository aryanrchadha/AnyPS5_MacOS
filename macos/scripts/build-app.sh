#!/usr/bin/env bash
# Builds "AnyPS5 Studio.app": the native relinker plus the SwiftUI front end.
#
#   macos/scripts/build-app.sh            # arm64 (Apple Silicon)
#   ARCHS="arm64 x86_64" macos/scripts/build-app.sh   # universal
#   DMG=1 macos/scripts/build-app.sh      # also produce a .dmg
#
# Requires Xcode or the Command Line Tools (swift, clang), and CMake.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MACOS="$ROOT/macos"
BUILD="${BUILD_DIR:-$ROOT/build-macos}"
ARCHS="${ARCHS:-arm64}"
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo 0.1)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="$BUILD/AnyPS5 Studio.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "build-app.sh must run on macOS." >&2
    exit 1
fi

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

step "Relinker (${ARCHS})"
generator=()
command -v ninja >/dev/null 2>&1 && generator=(-G Ninja)
cmake -S "$ROOT" -B "$BUILD/relinker" ${generator[@]+"${generator[@]}"} \
    -DCMAKE_BUILD_TYPE=Release \
    -DANYPS5_RELINKER_ONLY=ON \
    -DCMAKE_OSX_ARCHITECTURES="${ARCHS// /;}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build "$BUILD/relinker" --target relinker --parallel

step "AnyPS5 Studio (${ARCHS})"
swift_arch=()
for arch in $ARCHS; do swift_arch+=(--arch "$arch"); done
swift build --package-path "$MACOS" -c release "${swift_arch[@]}"
BIN_DIR="$(swift build --package-path "$MACOS" -c release "${swift_arch[@]}" --show-bin-path)"

step "Bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AnyPS5Studio" "$APP/Contents/MacOS/AnyPS5Studio"
cp "$BUILD/relinker/core/relinker/relinker" "$APP/Contents/MacOS/relinker"
sed -e "s/__VERSION__/${VERSION#v}/" -e "s/__BUILD__/${BUILD_NUMBER}/" \
    "$MACOS/Resources/Info.plist" > "$APP/Contents/Info.plist"

# The icon is drawn in SwiftUI (Design/AppIcon.swift); the app renders it at 1024 px.
ICON_PNG="$BUILD/AppIcon.png"
ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET" "$ICON_PNG"
mkdir -p "$ICONSET"
if "$BIN_DIR/AnyPS5Studio" --render-icon "$ICON_PNG" && [[ -s "$ICON_PNG" ]]; then
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
    echo "warning: icon rendering failed; the bundle uses the generic icon" >&2
    /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP/Contents/Info.plist"
fi

step "Sign (ad hoc)"
# Apple Silicon refuses unsigned arm64 code. Sign the helper first, then the bundle.
codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/relinker"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

"$APP/Contents/MacOS/relinker" >/dev/null 2>&1 && status=0 || status=$?
if [[ $status -ne 1 ]]; then
    echo "Bundled relinker smoke test failed: expected exit code 1 without arguments, got $status" >&2
    exit 1
fi

if [[ "${DMG:-0}" == "1" ]]; then
    step "Disk image"
    staging="$BUILD/dmg"
    rm -rf "$staging" "$BUILD/AnyPS5-Studio.dmg"
    mkdir -p "$staging"
    cp -R "$APP" "$staging/"
    ln -s /Applications "$staging/Applications"
    hdiutil create -volname "AnyPS5 Studio" -srcfolder "$staging" -ov -format UDZO "$BUILD/AnyPS5-Studio.dmg" >/dev/null
    echo "$BUILD/AnyPS5-Studio.dmg"
fi

step "Done"
echo "$APP"
