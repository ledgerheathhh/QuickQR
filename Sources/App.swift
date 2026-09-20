import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let accent = Color(red: 0.12, green: 0.49, blue: 0.38)
private let contentWidth: CGFloat = 368

@MainActor
final class QRModel: ObservableObject {
    @Published var text = ""
    @Published var inputFocusRequest = 0
    @Published var result: QRCode.Result?
    @Published var error: String?
    @Published var notice: String?
    private var generationTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    func generate() {
        generationTask?.cancel()
        notice = nil
        error = nil
        result = nil
        let input = text
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self?.text == input else { return }
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
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try result.png.write(to: url, options: .atomic)
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

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 11) {
                Image(systemName: "qrcode")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("QuickQR").font(.system(size: 19, weight: .semibold))
                    Text("随手输入，扫码即达").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Text("QuickQR 1.1 · 本地生成")
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

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("文字或链接").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button { model.paste(); model.inputFocusRequest += 1 } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                    .font(.system(size: 11, weight: .medium))
                    Button { model.text = ""; model.inputFocusRequest += 1 } label: {
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
                RoundedRectangle(cornerRadius: 16).fill(.white)
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
                            .foregroundStyle(model.error == nil ? accent.opacity(0.45) : Color.orange)
                        Text(model.error ?? "你的二维码会出现在这里")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.black.opacity(0.48))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .frame(width: 232, height: 232)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06)))

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
            .foregroundStyle(model.notice == nil ? Color.secondary : accent)
            .frame(height: 26)
            .accessibilityElement(children: .combine)
        }
        .padding(22)
        .frame(width: contentWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.text) { _ in model.generate() }
        .onAppear { model.inputFocusRequest += 1 }
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
        let hostingController = NSHostingController(rootView: ContentView(model: model))
        let contentSize = hostingController.sizeThatFits(
            in: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        hostingController.preferredContentSize = contentSize
        popover.contentViewController = hostingController
        popover.contentSize = contentSize
        DispatchQueue.main.async { self.showPopover() }
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
            let menu = NSMenu()
            menu.addItem(withTitle: "打开 QuickQR", action: #selector(openPopover), keyEquivalent: "")
                .target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出 QuickQR", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    @objc private func openPopover() { showPopover() }

    private func showPopover() {
        guard let button = item.button else { return }
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
