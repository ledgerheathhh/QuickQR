#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/qingma-test.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
if [[ -z "${DEVELOPER_DIR:-}" && -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "${TMPDIR:-/tmp}/qingma-module-cache" \
    "$ROOT/Sources/QRCode.swift" "$ROOT/Tests/QRCodeTests.swift" -o "$BUILD/QRCodeTests"
"$BUILD/QRCodeTests"
