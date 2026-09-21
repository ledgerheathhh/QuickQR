#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$ROOT/dist}"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/qingma-build.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT

# Use Apple's installed tools; no third-party packages.
if [[ -z "${DEVELOPER_DIR:-}" && -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
SWIFTC="$(xcrun --find swiftc)"
# Prefer Xcode's complete Swift runtime libraries when it is installed.
if [[ -x /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc ]]; then
    SWIFTC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
fi
SDK="$(xcrun --show-sdk-path)"
FLAGS=(-sdk "$SDK" -module-cache-path "${TMPDIR:-/tmp}/qingma-module-cache")

APP="$BUILD/QuickQR.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for ARCH in arm64 x86_64; do
    echo "Building $ARCH..."
    "$SWIFTC" "${FLAGS[@]}" -target "${ARCH}-apple-macosx13.0" -O -parse-as-library \
        "$ROOT/Sources/QRCode.swift" "$ROOT/Sources/History.swift" \
        "$ROOT/Sources/TextInput.swift" "$ROOT/Sources/App.swift" -o "$BUILD/QuickQR-$ARCH"
done
xcrun lipo -create "$BUILD/QuickQR-arm64" "$BUILD/QuickQR-x86_64" -output "$APP/Contents/MacOS/QuickQR"
xcrun lipo "$APP/Contents/MacOS/QuickQR" -verify_arch arm64
xcrun lipo "$APP/Contents/MacOS/QuickQR" -verify_arch x86_64
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
rm -rf "$DEST/QuickQR.app"
ditto "$APP" "$DEST/QuickQR.app"
echo "Built: $DEST/QuickQR.app (Universal: arm64 + x86_64)"
