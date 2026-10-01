import AppKit
import SwiftUI

private let accent = Color(red: 0.12, green: 0.49, blue: 0.38)
/// The popover's content width. Internal rather than private so `render-appearance.sh`
/// measures the views at exactly the width the app lays them out at.
let contentWidth: CGFloat = 368
/// Match the generator's measured height so page switching never resizes the popover.
/// `render-appearance.sh` checks the pair in both appearances.
private let historyHeight: CGFloat = 492

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
                        .frame(width: 24, height: 24)
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
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("更多选项")
                .accessibilityLabel("更多选项")
            }

            if model.showsHistory {
                HistoryView(history: model.history, model: model) { entry in
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
        .alert("清空所有历史记录？", isPresented: $model.confirmsHistoryClear) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive, action: model.clearHistory)
        } message: {
            Text("将删除本机保存的全部历史记录，此操作无法撤销。")
        }
        .onAppear { model.inputFocusRequest += 1 }
    }

    private var generator: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("文字或链接").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button(action: model.paste) {
                        Label(model.text.isEmpty ? "粘贴" : "粘贴并替换", systemImage: "doc.on.clipboard")
                            .frame(height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(brand)
                    .font(.system(size: 11, weight: .medium))
                    .help(model.text.isEmpty ? "粘贴剪贴板文字" : "替换全部内容，可按 ⌘Z 撤销")
                    Button(action: model.clear) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.text.isEmpty)
                    .help("清空内容，可按 ⌘Z 撤销")
                    .accessibilityLabel("清空内容")
                }
                TextInput(text: $model.text, focusRequest: model.inputFocusRequest)
                .frame(height: 96)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.09)))
                HStack {
                    Text(inputStatus)
                        .foregroundStyle(model.text.utf8.count > QRCode.maximumBytes ? Color.red : Color.secondary)
                    Spacer()
                    Text("\(model.text.utf8.count) / 2,000 字节")
                        .foregroundStyle(model.text.utf8.count > QRCode.maximumBytes ? Color.red :
                            model.text.utf8.count >= 1_800 ? Color.orange : Color.secondary)
                        .monospacedDigit()
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .help("最多 2,000 个 UTF-8 字节；中文和 emoji 通常占多个字节")
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(cardFill)
                if let result = model.result {
                    Button(action: model.enlargeQRCode) {
                        Image(nsImage: result.image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canExport)
                    .help("点击放大二维码，按 Esc 关闭预览")
                    .accessibilityLabel("放大二维码")
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
            .overlay(alignment: .bottom) {
                if model.isGenerating {
                    Text("更新中…")
                        .font(.system(size: 11))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                }
            }

            HStack(spacing: 10) {
                Button(action: model.copyImage) {
                    Label(model.imageCopied ? "已复制" : "复制图片", systemImage: model.imageCopied ? "checkmark" : "doc.on.doc")
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
            .disabled(!model.canExport)

            NoticeView(model: model, defaultMessage: "离线生成 · 内容不会上传")
        }
    }

    private var inputStatus: String {
        let count = model.text.utf8.count
        if count > QRCode.maximumBytes { return "超出 \(count - QRCode.maximumBytes) 字节" }
        if model.isGenerating { return "正在更新二维码…" }
        if count >= 1_800 { return "接近上限，建议放大扫码" }
        return "输入后自动生成"
    }
}

private struct NoticeView: View {
    @ObservedObject var model: QRModel
    @Environment(\.colorScheme) private var colorScheme
    let defaultMessage: String

    private var color: Color {
        guard let notice = model.notice else { return .secondary }
        switch notice.kind {
        case .success: return brandColor(colorScheme)
        case .warning: return .orange
        case .failure: return .red
        }
    }

    private var icon: String {
        guard let notice = model.notice else { return "lock.shield" }
        switch notice.kind {
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .failure: return "xmark.circle"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(model.notice?.message ?? defaultMessage).lineLimit(2)
                .accessibilityElement(children: .combine)
            if model.notice?.offersUndo == true {
                Button("撤销", action: model.undoHistoryRemoval)
                    .buttonStyle(.plain)
                    .underline()
                    .frame(height: 24)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(color)
        .frame(height: 26)
    }
}

private struct HistoryView: View {
    @ObservedObject var history: QRHistoryStore
    @ObservedObject var model: QRModel
    @Environment(\.colorScheme) private var colorScheme
    let onSelect: (QRHistoryEntry) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("历史记录")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("清空", role: .destructive) { model.confirmsHistoryClear = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(history.entries.isEmpty ? Color.secondary : Color.red)
                    .disabled(history.entries.isEmpty)
                    .frame(height: 24)
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
                                        if let host = entry.linkHost {
                                            Text(host)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                        }
                                        Text(entry.text)
                                            .font(.system(size: 12))
                                            .foregroundStyle(entry.linkHost == nil ? Color.primary : Color.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        TimelineView(.periodic(from: .now, by: 60)) { context in
                                            Text(entry.timeLabel(relativeTo: context.date))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(entry.text)

                                Button { model.removeHistory(entry) } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain)
                                .help("删除这条记录")
                                .accessibilityLabel("删除这条记录")
                            }
                            .padding(11)
                            .background(Color.primary.opacity(model.hoveredHistoryEntry == entry.id ? 0.09 : 0.045), in: RoundedRectangle(cornerRadius: 10))
                            .onHover { model.hoveredHistoryEntry = $0 ? entry.id : nil }
                        }
                    }
                }
            }

            NoticeView(model: model, defaultMessage: "最多保留 20 条 · 仅存储在本机")
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
        appMenu.addItem(withTitle: "关闭预览", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
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
