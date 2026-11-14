#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
read -ra ARCHITECTURES <<<"${ARCHS:-$(uname -m)}"
IDENTITY="${SIGN_IDENTITY:--}"
ARCH_FLAGS=()
for arch in "${ARCHITECTURES[@]}"; do
    ARCH_FLAGS+=(-arch "$arch")
done
BUILD_FLAGS=(-c release "${ARCH_FLAGS[@]/#-arch/--arch}")

swift build "${BUILD_FLAGS[@]}"
PRODUCTS="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

APP="build/Trouser.app"
PLUGIN="$APP/Contents/PlugIns/TrouserBundle.bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PLUGIN/Contents/MacOS"
cp "$PRODUCTS/Trouser" "$APP/Contents/MacOS/"
/usr/bin/strip -S "$APP/Contents/MacOS/Trouser"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

cp Bundle/Info.plist "$PLUGIN/Contents/"
clang -bundle -fobjc-arc -fmodules -O2 -Wall -Werror -mmacosx-version-min=14.0 \
    -Wno-deprecated-declarations -Wno-unused-parameter \
    "${ARCH_FLAGS[@]}" \
    -I Sources/TrouserBridge \
    -framework Foundation -framework AppKit -framework WebKit \
    Bundle/*.m -o "$PLUGIN/Contents/MacOS/TrouserBundle"
codesign --force --sign "$IDENTITY" --options runtime "$PLUGIN"

codesign --force --sign "$IDENTITY" --options runtime --entitlements Resources/Trouser.entitlements "$APP"
echo "$APP"
