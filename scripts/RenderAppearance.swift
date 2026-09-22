import AppKit
import SwiftUI

// Renders the real `ContentView` offscreen in both system appearances, so a visual
// change can be inspected — or diffed against another build — without launching the
// app, without a screen-recording permission, and without disturbing the menu bar.
//
// This file is not part of the app. `render-appearance.sh` cuts the `@main` entry
// point out of a copy of `Sources/App.swift`, drops this file beside it as
// `main.swift`, and compiles the two together. The views drawn here are therefore
// the ones that ship, not a reimplementation of them.

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: render-appearance <output-directory>\n".utf8))
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// An offscreen render still needs a running app: `NSHostingView` resolves semantic
// colours and control appearance against `NSApplication`. `.prohibited` keeps it out
// of the Dock and off the screen.
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

// The history store persists to `UserDefaults`. Keep it out of the app's own domain,
// and out of the rendered scenes' way of each other.
let defaultsSuite = "quickqr.appearance-render"
let defaults = UserDefaults(suiteName: defaultsSuite)!
defaults.removePersistentDomain(forName: defaultsSuite)

let sample = "https://example.com/你好?from=轻码"

/// One popover state to capture.
struct Scene {
    let name: String
    /// The popover page this scene shows. Both pages have to report the same height,
    /// or the popover resizes when the header button toggles between them.
    let page: String
    let configure: @MainActor (QRModel) -> Void
}

/// Built on the main actor, because every scene configures a `QRModel`.
@MainActor
var scenes: [Scene] {
    [
        Scene(name: "generator-empty", page: "generator") { _ in },
        Scene(name: "generator-code", page: "generator") { $0.result = try? QRCode.generate(sample) },
        Scene(name: "generator-error", page: "generator") {
            $0.error = QRCode.Failure.tooLong.errorDescription
        },
        Scene(name: "history-empty", page: "history") { $0.showsHistory = true },
        Scene(name: "history-filled", page: "history") {
            $0.history.record(sample)
            $0.history.record("QuickQR 本地生成，内容不会上传")
            $0.history.record("https://developer.apple.com/documentation/appkit")
            $0.showsHistory = true
        }
    ]
}

let appearances: [(label: String, name: NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

/// Draws one scene and returns the size the popover would take for it.
@MainActor
func render(_ scene: Scene, appearanceName: NSAppearance.Name, to url: URL) -> NSSize? {
    let model = QRModel(history: QRHistoryStore(defaults: defaults, storageKey: "history", limit: 20))
    scene.configure(model)

    // Measure and draw through a hosting controller, because that is what the app
    // puts inside its popover — the size measured here is the size the popover takes.
    // `NSHostingView.fittingSize` agrees with it on these views; the controller is
    // used so that measuring and drawing come from the same object.
    let controller = NSHostingController(rootView: ContentView(model: model))
    let fitting = controller.sizeThatFits(
        in: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
    )

    let view = controller.view
    let appearance = NSAppearance(named: appearanceName)!
    view.appearance = appearance

    // The view still has to belong to a window before it will lay out or draw.
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: fitting),
        styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.appearance = appearance
    window.contentViewController = controller
    view.frame = NSRect(origin: .zero, size: fitting)
    window.layoutIfNeeded()
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()

    guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: representation)
    guard let data = representation.representation(using: .png, properties: [:]) else { return nil }
    do { try data.write(to: url) } catch { return nil }
    return fitting
}

@MainActor
func run() -> Int32 {
    var sizes: [String: NSSize] = [:]
    var failures: [String] = []
    var rows: [(scene: String, label: String, size: NSSize)] = []

    for scene in scenes {
        for (label, appearanceName) in appearances {
            let file = "\(scene.name)-\(label).png"
            let url = outputDirectory.appendingPathComponent(file)
            guard let size = render(scene, appearanceName: appearanceName, to: url) else {
                failures.append("could not render \(file)")
                continue
            }
            rows.append((scene.name, label, size))
            // Every scene on the same page must measure the same, in both appearances.
            if let seen = sizes[scene.page], seen != size {
                failures.append(
                    "the \(scene.page) page measures \(Int(size.width))x\(Int(size.height)) pt here "
                    + "but \(Int(seen.width))x\(Int(seen.height)) pt elsewhere"
                )
            }
            sizes[scene.page] = size
        }
    }

    // The height of the history page is tuned against the generator page. If they
    // drift apart, the popover changes size when the header button is toggled.
    if let generator = sizes["generator"], let history = sizes["history"], generator != history {
        failures.append(
            "the generator page is \(Int(generator.height)) pt tall but the history page is "
            + "\(Int(history.height)) pt, so the popover would resize when they are toggled"
        )
    }

    print("QuickQR appearance render")
    print("  output: \(outputDirectory.path)")
    for row in rows {
        let size = "\(Int(row.size.width))x\(Int(row.size.height))"
        print(String(format: "    %-18@ %-6@ %@ pt", row.scene as NSString, row.label as NSString, size as NSString))
    }
    print("  wrote \(rows.count) images")
    guard failures.isEmpty else {
        for failure in failures { print("  FAIL: \(failure)") }
        return 1
    }
    print("  both pages measure the same, in both appearances")
    return 0
}

// Top-level code in `main.swift` is not main-actor isolated, and everything above has
// to be. We are already on the main thread, so asserting that is safe.
exit(MainActor.assumeIsolated { run() })
