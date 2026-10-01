import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class QRModel: ObservableObject {
    struct Notice {
        enum Kind: Equatable { case success, warning, failure }
        let message: String
        let kind: Kind
        var offersUndo = false
    }

    @Published var text = "" {
        didSet { if text != oldValue { generate() } }
    }
    @Published var inputFocusRequest = 0
    @Published private(set) var result: QRCode.Result?
    @Published private(set) var isGenerating = false
    @Published private(set) var error: String?
    @Published private(set) var notice: Notice?
    @Published private(set) var imageCopied = false
    @Published var showsHistory = false
    @Published var confirmsHistoryClear = false
    @Published var hoveredHistoryEntry: UUID?
    let history: QRHistoryStore
    /// Reopens the transient popover after a separate save panel closes.
    var restorePopover: (() -> Void)?
    private var resultText: String?
    private var shouldRecordAutomatically = false
    private var generationTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var previewWindow: NSWindowController?
    private let generateCode: @Sendable (String) throws -> QRCode.Result

    init(
        history: QRHistoryStore? = nil,
        generateCode: @escaping @Sendable (String) throws -> QRCode.Result = { try QRCode.generate($0) }
    ) {
        self.history = history ?? QRHistoryStore()
        self.generateCode = generateCode
    }

    var canExport: Bool { result != nil && resultText == text && !isGenerating }

    func generate() {
        generationTask?.cancel()
        clearNotice()
        error = nil
        shouldRecordAutomatically = false
        let input = text
        do {
            _ = try QRCode.validate(input)
        } catch {
            result = nil
            resultText = nil
            isGenerating = false
            if error as? QRCode.Failure != .empty { self.error = error.localizedDescription }
            return
        }
        // Preserve the preview while typing, but export only a result for current text.
        shouldRecordAutomatically = true
        isGenerating = true
        let generateCode = self.generateCode
        generationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                try Task.checkCancellation()
                let generated = try await Task.detached(priority: .userInitiated) {
                    try generateCode(input)
                }.value
                try Task.checkCancellation()
                guard let self, self.text == input else { return }
                self.resultText = input
                self.result = generated
                self.isGenerating = false
                // Avoid persisting every intermediate value during typing.
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try Task.checkCancellation()
                guard self.text == input, self.shouldRecordAutomatically else { return }
                self.shouldRecordAutomatically = false
                self.history.record(input)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self, self.text == input else { return }
                self.result = nil
                self.resultText = nil
                self.isGenerating = false
                self.error = error.localizedDescription
            }
        }
    }

    func paste() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
            showNotice("剪贴板中没有可用的文字", kind: .warning)
            return
        }
        text = value
        inputFocusRequest += 1
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
        copyImage(to: .general)
    }

    func copyImage(to board: NSPasteboard) {
        guard canExport, let result else { return }
        board.clearContents()
        let item = NSPasteboardItem()
        item.setData(result.png, forType: .png)
        if let tiff = result.image.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        if board.writeObjects([item]) {
            shouldRecordAutomatically = false
            history.record(text)
            showNotice("二维码图片已复制", kind: .success)
            imageCopied = true
        } else {
            showNotice("复制失败，请重试", kind: .failure)
        }
    }

    func saveImage() {
        guard canExport, let result else { return }
        let savedText = text
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "二维码.png"
        panel.title = "保存二维码"
        panel.prompt = "保存"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            self.restorePopover?()
            guard response == .OK, let url = panel.url else { return }
            self.write(result.png, text: savedText, to: url)
        }
    }

    func write(_ png: Data, text: String, to url: URL) {
        do {
            try png.write(to: url, options: .atomic)
            if self.text == text { shouldRecordAutomatically = false }
            history.record(text)
            showNotice("二维码已保存", kind: .success)
        } catch {
            showNotice("保存失败：\(error.localizedDescription)", kind: .failure)
        }
    }

    func removeHistory(_ entry: QRHistoryEntry) {
        // Explicit removal wins over this input's pending automatic record.
        if entry.text == text { shouldRecordAutomatically = false }
        clearNotice()
        history.remove(entry)
        showNotice("记录已删除", kind: .success, offersUndo: true)
    }

    func undoHistoryRemoval() {
        history.undoRemoval()
        showNotice("记录已恢复", kind: .success)
    }

    func clearHistory() {
        shouldRecordAutomatically = false
        clearNotice()
        history.removeAll()
        showNotice("历史记录已清空", kind: .success)
    }

    func showNotice(_ message: String, kind: Notice.Kind, offersUndo: Bool = false) {
        clearNotice()
        notice = Notice(message: message, kind: kind, offersUndo: offersUndo)
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: offersUndo ? 5_000_000_000 : 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.clearNotice()
        }
    }

    private func clearNotice() {
        noticeTask?.cancel()
        if notice?.offersUndo == true { history.discardRemoval() }
        notice = nil
        imageCopied = false
    }

    func enlargeQRCode() {
        guard canExport, let result else { return }
        previewWindow?.close()
        let window = QRPreviewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.title = "二维码预览"
        window.minSize = NSSize(width: 320, height: 320)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView:
            Image(nsImage: result.image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .accessibilityLabel("放大的二维码")
        )
        window.center()
        previewWindow = NSWindowController(window: window)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

private final class QRPreviewWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }
}
