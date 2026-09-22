import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let accent = Color(red: 0.12, green: 0.49, blue: 0.38)
/// The popover's content width. Internal rather than private so `render-appearance.sh`
/// measures the views at exactly the width the app lays them out at.
let contentWidth: CGFloat = 368
/// Height of the history page, tuned to match the generator page exactly — the two
/// branches have to measure the same, or the popover resizes when the header button
/// toggles between them. 44 (padding) + 44 (header) + 18 (spacing) + 483 = 589, which
/// is what the generator page measures.
///
/// Measure this by hosting both pages in a real `NSPopover` and reading the window
/// height, which is the content height plus 26: both pages have to give 394x615. The
/// generator page is the one to match, because its height comes from its own content
/// and this constant cannot move it. `render-appearance.sh` checks the pair.
private let historyHeight: CGFloat = 483

/// The brand green for text and glyphs. `accent` is tuned for a light surface —
/// 5.0:1 against white, but only 3.3:1 against the dark window — so the dark
/// appearance gets a lifted variant at 6.8:1. Filled controls keep the deep value
/// on purpose: a prominent button pairs it with white text, which the light green
/// cannot carry.
private func brandColor(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(red: 0.30, green: 0.72, blue: 0.57) : accent
}

/// Large decorative brand glyphs. The 45% that softens the mark on a light card
/// all but erases it on a dark one.
private func brandGlyphColor(_ scheme: ColorScheme) -> Color {
    brandColor(scheme).opacity(scheme == .dark ? 0.85 : 0.45)
}

@MainActor
final class QRModel: ObservableObject {
    @Published var text = ""
    @Published var inputFocusRequest = 0
    @Published var result: QRCode.Result?
    @Published var error: String?
    @Published var notice: String?
    @Published var showsHistory = false
    let history: QRHistoryStore
    /// Set by the app delegate. Called once a separate window owned by the app —
    /// the save panel — has closed, so the popover is on screen again before the
    /// outcome is reported. A `.transient` popover is dismissed by a click outside
    /// it, and every click in the save panel counts as one.
    var restorePopover: (() -> Void)?
    private var generationTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    init(history: QRHistoryStore? = nil) {
        self.history = history ?? QRHistoryStore()
    }

    func generate() {
        generationTask?.cancel()
        notice = nil
        error = nil
        let input = text
        // Keep the previous code on screen while the new one is being debounced, so
        // typing does not flash the placeholder. It is cleared only when there is
        // nothing left to show: empty input, or a generation that failed.
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result = nil
            return
        }
        generationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                try Task.checkCancellation()
                let generated = try await Task.detached(priority: .userInitiated) {
                    try QRCode.generate(input)
                }.value
                try Task.checkCancellation()
                guard self?.text == input else { return }
                self?.result = generated
                // Keep normal typing from filling history with every intermediate value.
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try Task.checkCancellation()
                guard self?.text == input else { return }
                self?.history.record(input)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self?.text == input else { return }
                // An error must not leave the code for the previous input on screen.
                self?.result = nil
                self?.error = error.localizedDescription
            }
        }
    }

    func paste() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
            showNotice("剪贴板中没有可用的文字")
            return
        }
        text = value
    }

    func clear() {
        text = ""
        inputFocusRequest += 1
    }

    func restore(_ entry: QRHistoryEntry) {
        text = entry.text
        inputFocusRequest += 1
    }

    func copyImage() {
        guard let result else { return }
        let board = NSPasteboard.general
        board.clearContents()
        let item = NSPasteboardItem()
        item.setData(result.png, forType: .png)
        if let tiff = result.image.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        showNotice(board.writeObjects([item]) ? "二维码图片已复制" : "复制失败，请重试")
    }

    func saveImage() {
        guard let result else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "二维码.png"
        panel.title = "保存二维码"
        panel.prompt = "保存"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        // Present the panel without blocking, and re-present the popover before
        // reporting. `runModal()` would sit on the run loop until the user was
        // done, by which point a transient popover has already been dismissed by
        // the first click inside the panel — the "saved" notice would have had
        // nowhere to appear. A sheet is not an option either: it would be attached
        // to the popover's own window and sized to it.
        panel.begin { [weak self] response in
            guard let self else { return }
            self.restorePopover?()
            guard response == .OK, let url = panel.url else { return }
            self.write(result.png, to: url)
        }
    }

    private func write(_ png: Data, to url: URL) {
        do {
            try png.write(to: url, options: .atomic)
            showNotice("二维码已保存")
        } catch {
            showNotice("保存失败：\(error.localizedDescription)")
        }
    }

    func showNotice(_ message: String) {
        noticeTask?.cancel()
        notice = message
        noticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { notice = nil }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: QRModel
    @Environment(\.colorScheme) private var colorScheme

    private var brand: Color { brandColor(colorScheme) }
    private var glyph: Color { brandGlyphColor(colorScheme) }

    /// The card is white whenever a code is on screen — a camera needs that
    /// contrast — but with nothing to show there is no reason to hold a 232 pt
    /// white slab on a dark window. The placeholder borrows the same 4% surface
    /// tint the history rows use, so it follows the appearance on its own.
    private var cardFill: Color {
        model.result != nil ? .white : Color.primary.opacity(0.04)
    }

    private var cardBorder: Color {
        model.result != nil ? Color.black.opacity(0.06) : Color.primary.opacity(0.09)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 11) {
                Image(systemName: "qrcode")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(brand)
                    .frame(width: 44, height: 44)
                    .background(brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("QuickQR").font(.system(size: 19, weight: .semibold))
                    Text("随手输入，扫码即达").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.showsHistory.toggle()
                } label: {
                    Image(systemName: model.showsHistory ? "qrcode" : "clock.arrow.circlepath")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(model.showsHistory ? "返回生成器" : "历史记录")
                .accessibilityLabel(model.showsHistory ? "返回生成器" : "历史记录")
                Menu {
                    Text("QuickQR 1.2 · 本地生成")
                    Divider()
                    Button("退出 QuickQR", action: { NSApp.terminate(nil) }).keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 18)).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("更多选项")
                .accessibilityLabel("更多选项")
            }

            if model.showsHistory {
                HistoryView(history: model.history) { entry in
                    model.restore(entry)
                    model.showsHistory = false
                }
            } else {
                generator
            }
        }
        .padding(22)
        .frame(width: contentWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.text) { _ in model.generate() }
        .onAppear { model.inputFocusRequest += 1 }
    }

    private var generator: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("文字或链接").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button { model.paste(); model.inputFocusRequest += 1 } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(brand)
                    .font(.system(size: 11, weight: .medium))
                    Button(action: model.clear) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.text.isEmpty)
                    .help("清空内容")
                    .accessibilityLabel("清空内容")
                }
                TextInput(text: $model.text, focusRequest: model.inputFocusRequest)
                .frame(height: 96)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.09)))
                HStack {
                    Text("输入后自动生成")
                    Spacer()
                    Text("\(model.text.utf8.count) / 2,000 字节")
                        .foregroundStyle(model.text.utf8.count > QRCode.maximumBytes ? Color.red : Color.secondary)
                        .monospacedDigit()
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(cardFill)
                if let result = model.result {
                    Image(nsImage: result.image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                        .accessibilityLabel("已生成的二维码")
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: model.error == nil ? "qrcode.viewfinder" : "exclamationmark.circle")
                            .font(.system(size: 49, weight: .ultraLight))
                            .foregroundStyle(model.error == nil ? glyph : Color.orange)
                        Text(model.error ?? "你的二维码会出现在这里")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .frame(width: 232, height: 232)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(cardBorder))

            HStack(spacing: 10) {
                Button(action: model.copyImage) {
                    Label("复制图片", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                Button(action: model.saveImage) {
                    Label("保存 PNG", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("s", modifiers: .command)
            }
            .controlSize(.large)
            .disabled(model.result == nil)

            HStack(spacing: 5) {
                Image(systemName: model.notice == nil ? "lock.shield" : "checkmark.circle")
                Text(model.notice ?? "离线生成 · 内容不会上传")
                    .lineLimit(2)
            }
            .font(.system(size: 10))
            .foregroundStyle(model.notice == nil ? Color.secondary : brand)
            .frame(height: 26)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct HistoryView: View {
    @ObservedObject var history: QRHistoryStore
    @Environment(\.colorScheme) private var colorScheme
    let onSelect: (QRHistoryEntry) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("历史记录")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("清空", role: .destructive, action: history.removeAll)
                    .buttonStyle(.plain)
                    .foregroundStyle(history.entries.isEmpty ? Color.secondary : Color.red)
                    .disabled(history.entries.isEmpty)
            }

            if history.entries.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 42, weight: .ultraLight))
                        .foregroundStyle(brandGlyphColor(colorScheme))
                    Text("还没有历史记录")
                        .font(.system(size: 13, weight: .medium))
                    Text("成功生成的内容会自动保存在这里")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(history.entries) { entry in
                            HStack(spacing: 10) {
                                Button { onSelect(entry) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(entry.text)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Text(entry.createdAt, style: .relative)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button { history.remove(entry) } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("删除这条记录")
                                .accessibilityLabel("删除这条记录")
                            }
                            .padding(11)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }

            HStack(spacing: 5) {
                Image(systemName: "lock.shield")
                Text("最多保留 20 条 · 仅存储在本机")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .frame(height: historyHeight)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let model = QRModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installEditingMenu()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "qrcode", accessibilityDescription: "QuickQR：生成二维码")
            button.image?.isTemplate = true
            button.toolTip = "QuickQR · 二维码生成器"
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        model.restorePopover = { [weak self] in
            // Only while this app still owns the screen. `begin` presents the save
            // panel as a modeless window, so the user may have moved on to another
            // app by the time it closes — reopening the popover would steal focus.
            guard let self, NSApp.isActive else { return }
            self.showPopover()
        }
        let hostingController = NSHostingController(rootView: ContentView(model: model))
        let contentSize = hostingController.sizeThatFits(
            in: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        hostingController.preferredContentSize = contentSize
        popover.contentViewController = hostingController
        popover.contentSize = contentSize
        showInitialPopoverWhenReady()
    }

    private func installEditingMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 QuickQR", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [
            ("撤销", "undo:", "z"), ("剪切", "cut:", "x"),
            ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")
        ] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            // The menu opens from the same status item the popover hangs from, so
            // leaving the popover up would stack the two on top of each other.
            if popover.isShown { popover.performClose(nil) }
            presentContextMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    /// Opens the right-click menu under the status item.
    ///
    /// There is no supported "show this menu now" call on `NSStatusItem`.
    /// `popUpMenu(_:)` is only the Swift name of the `popUpStatusItemMenu:`
    /// selector that AppKit deprecated in macOS 10.14, with the advice to use the
    /// `menu` property instead. So: assign the menu, let the button track it, then
    /// clear it. Clearing is the part that matters — a status item that owns a
    /// menu stops calling its action altogether.
    private func presentContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 QuickQR", action: #selector(openPopover), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 QuickQR", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openPopover() { showPopover() }

    /// Resolves the status item's on-screen anchor, or `nil` while the status bar
    /// window is still in its transient, unpositioned state.
    ///
    /// A freshly created status item reports a window that already exists but still
    /// carries the default frame `{{0, 0}, {38, 0}}` until the window server places
    /// it. Converting through that frame yields an anchor straddling the screen
    /// origin — the bottom-left corner — which is exactly where the popover would
    /// then be pinned. The window is also observed mid-flight, below the menu bar or
    /// hanging off the bottom edge, so every one of these states has to be rejected:
    /// a zero-height window, an anchor outside its own window, or a window that has
    /// not reached the top strip of its screen.
    private func resolvedAnchor() -> NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        button.layoutSubtreeIfNeeded()
        let frame = window.frame
        guard frame.width > 0, frame.height > 0, let screen = window.screen else { return nil }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard anchor.width > 0, anchor.height > 0, frame.intersects(anchor) else { return nil }
        // The status bar window occupies the topmost strip of its screen, or sits
        // just above the top edge while an auto-hiding menu bar stays hidden.
        guard frame.maxY >= screen.frame.maxY - 1 else { return nil }
        return anchor
    }

    private func showInitialPopoverWhenReady(
        previousAnchor: NSRect? = nil,
        attempt: Int = 0
    ) {
        guard !popover.isShown else { return }
        guard let anchor = resolvedAnchor() else {
            retryInitialPopover(previousAnchor: nil, attempt: attempt)
            return
        }
        if anchor == previousAnchor {
            showPopover()
        } else {
            retryInitialPopover(previousAnchor: anchor, attempt: attempt)
        }
    }

    private func retryInitialPopover(previousAnchor: NSRect?, attempt: Int) {
        // ~1 s of fast polls covers the normal case; the slower back-off covers
        // machines where the window server takes longer to place the status item.
        // Give up rather than open at an anchor that is still untrustworthy.
        guard attempt < 60 else { return }
        let delay: TimeInterval = attempt < 20 ? 0.05 : 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.showInitialPopoverWhenReady(previousAnchor: previousAnchor, attempt: attempt + 1)
        }
    }

    private func showPopover() {
        guard !popover.isShown else { return }
        guard let button = item.button else { return }
        // Never anchor to a status bar window that has not been placed yet: wait for
        // it instead of pinning the popover to a stale frame.
        guard resolvedAnchor() != nil else {
            showInitialPopoverWhenReady()
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }
}

@main
enum QRBarApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
