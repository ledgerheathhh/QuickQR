#!/bin/bash
# Renders the app's popover offscreen in both system appearances, for inspecting a
# visual change or diffing one build against another.
#
# The app is a `@main` executable, so its views cannot just be linked into a second
# program. This script copies the sources, cuts the entry point out of App.swift, and
# compiles them together with scripts/RenderAppearance.swift as `main.swift`. Nothing
# built here is part of the shipped app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$ROOT/dist/appearance}"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/qingma-render.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT

if ! grep -q '^@main$' "$ROOT/Sources/App.swift"; then
    echo "error: no '@main' line in Sources/App.swift; the renderer strips it to reuse the real views" >&2
    exit 1
fi

# Use Apple's installed tools; no third-party packages.
SWIFTC="$(xcrun --find swiftc)"
# Prefer Xcode's complete Swift runtime libraries when it is installed.
if [[ -x /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc ]]; then
    SWIFTC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
fi
SDK="$(xcrun --show-sdk-path)"

# Everything the app is made of, minus its entry point. Copying the whole directory
# rather than a fixed list keeps this working when a source file is added.
cp "$ROOT/Sources/"*.swift "$BUILD/"
awk '/^@main$/{exit} {print}' "$ROOT/Sources/App.swift" > "$BUILD/App.swift"
cp "$ROOT/scripts/RenderAppearance.swift" "$BUILD/main.swift"

"$SWIFTC" -sdk "$SDK" -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "${TMPDIR:-/tmp}/qingma-module-cache" \
    "$BUILD"/*.swift -o "$BUILD/render"
"$BUILD/render" "$DEST"
