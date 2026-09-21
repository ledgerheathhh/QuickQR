# QuickQR

A native macOS menu bar QR code generator, built with SwiftUI, AppKit, and the system Core Image, with no third-party dependencies.

## Usage

1. After building from source as described below, double-click `dist/QuickQR.app`, or drag it into "Applications" and open it. If an older 「轻码」 build is installed, quit the old app first, then use the new version.
2. Click the QR code icon in the menu bar at the top of the screen, and enter text or a link, or click "Paste".
3. The QR code updates automatically a moment after you stop typing; click "Copy Image" or "Save PNG".
4. Click the history button in the header to reopen any of the latest 20 generated items, or delete records you no longer need.
5. Click outside the popover to dismiss it; the content is kept until you quit the app. Right-click the menu bar icon to quit.

The app shows no Dock icon. All content is generated locally: it does not connect to the network, and its 20-item history stays in the current macOS user's local preferences. It never reads the clipboard on its own; it reads the clipboard only when you click Paste or use the system paste shortcut. Input preserves original line breaks and leading/trailing spaces, and blank content produces no QR code.

Keyboard shortcuts are available while the popover is open:

| Action | Shortcut |
| --- | --- |
| Paste text | ⌘V |
| Select all text | ⌘A |
| Copy QR code image | ⇧⌘C |
| Save PNG | ⌘S |
| Quit | ⌘Q |

If you want the app to launch at login, you can add it to macOS "Login Items" yourself. This version does not modify system login items.

## Output and limits

- UTF-8 text, up to 2,000 bytes; Chinese characters and emoji usually occupy multiple bytes.
- The PNG uses black modules, a white background, a four-module quiet zone, and M-level error correction; it is scaled by integer factors, so the output side length varies with the content and is usually close to 1,024 pixels.
- The longer the content, the denser the QR code; when scanning longer content, it is advisable to save the image and zoom in.
- The bundled app is a Universal build: the same app contains both Apple Silicon (arm64) and Intel (x86_64) architectures, and the deployment target for both is macOS 13.0 or later; the actual runtime verification is as recorded at the end of this document.
- The app uses a local ad-hoc signature, with no Developer ID signing or Apple notarization. It is suitable for local use; public distribution requires formal signing, notarization, and additional testing on target systems.

## Running in Xcode

The repository already contains `QuickQR.xcodeproj` and a shared scheme. Double-click `QuickQR.xcodeproj`, select the `QuickQR` scheme and `My Mac`, and press `⌘R` to run.

After launching, no ordinary window appears; the QR code icon appears in the macOS menu bar. Click the icon to open the popover; press `⌘.` to stop running. Press `⌘U` to run the default unit tests.

The project uses macOS 13.0 as its minimum deployment version and requires no third-party dependencies or Apple Developer Team. Xcode will run it with a local ad-hoc signature; if Xcode asks you to choose a Team, you can turn off automatic signing under Target → Signing & Capabilities, or keep the local ad-hoc signing settings.

## Building from the command line

After installing Apple Command Line Tools or Xcode, run the following in the source directory:

```sh
bash build.sh
```

The build script compiles arm64 and x86_64 separately, then uses `lipo` to merge them into `dist/QuickQR.app`, copies the fixed app icon, and signs it. You can pass in an output directory:

```sh
bash build.sh /path/to/output
```

The script uses the Apple SDK and the Swift compiler; when `/Applications/Xcode.app` is installed, it prefers the Swift toolchain bundled there, which contains complete dual-architecture compatibility libraries, and otherwise uses the Command Line Tools. The SDK path can be specified through `DEVELOPER_DIR`. No third-party packages need to be installed, and no network access is required.

After installing the full Xcode, running `bash test.sh` runs the stable input-validation unit tests through the shared scheme. Core Image and Vision read-back are graphics integration tests and are skipped by default; run them explicitly in an ordinary macOS terminal that has access to the system graphics services:

```sh
QUICKQR_RUN_VISION_TESTS=1 bash test.sh
```

Builds and graphics integration tests are kept separate, so that graphics services in a restricted execution environment cannot block app packaging.

## Files

- `Sources/App.swift`: menu bar, popover, clipboard, and file saving.
- `Sources/History.swift`: local, deduplicated 20-item history storage.
- `Sources/QRCode.swift`: QR code generation, quiet zone, and PNG encoding.
- `QuickQR.xcodeproj`: macOS app project that can be run directly in Xcode.
- `Tests/QRCodeTests.swift`: uses XCTest to precisely verify input boundaries, and provides Apple Vision read-back tests that can be explicitly enabled.
- `Resources/AppIcon.icns`: the fixed app icon shared by the Xcode and script builds.
- `scripts/MakeIcon.swift`: source-generation tool for the app icon.
- `Info.plist`: app bundle configuration.

## Verification records

Verification of the current unreleased fixes:

- Both the Xcode Release build and `build.sh` build successfully; the bundle identifier is uniformly `local.quickqr.app`, and the artifacts contain the same app icon.
- Both build paths produce an `x86_64 arm64` Universal main executable, and the minimum system version is macOS 13.0 for both.
- `bash test.sh` passes 8 unit tests covering input validation, text editing, and local history; the graphics integration test is skipped by default.
- Running the graphics integration tests explicitly in the current restricted execution environment still returns a generation failure from Core Image; Vision read-back and UI regression need to be completed in an ordinary macOS graphics session.

Version 1.2 update verification:

- The first-launch popover waits for a valid, stable menu-bar anchor before opening; launch and relaunch checks showed it attached below the QuickQR status item.
- Generated content is stored in a local, deduplicated 20-item history. The history UI, restore action, and persistence across an app relaunch were verified with the packaged app.
- The packaged app remains a signed Universal binary containing `x86_64 arm64`.

Version 1.1 (QuickQR) update verification:

- The app bundle, main executable, popover title, menus, and menu bar tooltip uniformly use the English name QuickQR, while the functional copy remains in Chinese.
- Both arm64 and x86_64 compile successfully; the build used the complete Swift toolchain from the local Xcode, avoiding the warning that the current Command Line Tools lack x86_64 compatibility libraries.
- `lipo` confirms that the main executable contains both `x86_64 arm64`; `vtool` confirms that the minimum system version for both architectures is macOS 13.0.
- The app bundle configuration, build script syntax, and signature pass strict validation.
- This change only modified the name and the build packaging and did not change the QR code generation logic; no UI testing was repeated, and no verification was run on a real Intel machine.

Version 1.0 was verified on Apple Silicon, macOS 27.0 (the UI records below come from 「轻码」 before the rename):

- Native Swift compilation succeeded; the app bundle `Info.plist` validation and the ad-hoc signature passed strict validation.
- The app was actually launched and the menu bar popover was inspected; the text input area, QR code preview, and action buttons displayed correctly, and the layout was fine under the current system dark appearance.
- Through system paste, `https://example.com/你好?from=轻码` was entered; the interface preserved the complete Chinese link and generated the QR code in real time.
- After clicking "Copy Image", the app showed that the copy succeeded.
- Saving a PNG through the system file dialog succeeded; the exported file was checked and is a 1014 × 1014 pixel PNG.
- The automated read-back tests did not pass verification in this restricted command-line environment: Core Image's `createCGImage` returned `nil` (both by default and with CPU rendering), whereas the same generation code runs normally in the actual app. Independent Vision read-back of the exported image also encountered `com.apple.Vision Code=9: Could not build inference plan`. It therefore cannot be claimed that the 11 read-back checks passed.
- The code has not yet been scanned with a real phone, and other macOS versions, Intel Macs, or cross-app image paste compatibility have not been verified.
