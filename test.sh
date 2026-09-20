#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/qingma-test.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
ARCH="$(uname -m)"
xcodebuild -project "$ROOT/QuickQR.xcodeproj" -scheme QuickQR \
    -configuration Debug -destination "platform=macOS,arch=$ARCH" \
    -derivedDataPath "$BUILD/DerivedData" CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=YES -quiet build-for-testing
xcrun xctest "$BUILD/DerivedData/Build/Products/Debug/QuickQRTests.xctest"
