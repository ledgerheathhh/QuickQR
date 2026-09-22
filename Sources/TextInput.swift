import AppKit
import SwiftUI

struct TextInput: NSViewRepresentable {
    @Binding var text: String
    var focusRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        let textView = QRTextView()
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? QRTextView else { return }
        context.coordinator.text = $text
        // While an input method is composing, `textView.string` carries candidates the
        // binding has never seen, and rewriting it here would discard them — which
        // happens on every SwiftUI update, including the one that publishes a freshly
        // generated code. An external change to the binding still goes through, but
        // uncommitted composition is left alone.
        let isExternalChange = text != context.coordinator.lastReported
        if textView.string != text, !textView.hasMarkedText() || isExternalChange {
            textView.string = text
            context.coordinator.lastReported = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
            textView.needsDisplay = true
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var focusRequest: Int?
        /// The last value this coordinator wrote into the binding, so that a change
        /// arriving from outside can be told apart from uncommitted composition.
        var lastReported = ""

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            lastReported = textView.string
            text.wrappedValue = textView.string
            textView.needsDisplay = true
        }
    }
}

final class QRTextView: NSTextView {
    private let placeholderStorage = NSTextStorage()
    private let placeholderLayout = NSLayoutManager()
    private let placeholderContainer = NSTextContainer()

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer()
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isRichText = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        drawsBackground = false
        font = .systemFont(ofSize: 13)
        textColor = .labelColor
        textContainerInset = NSSize(width: 12, height: 10)
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = .width
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        setAccessibilityLabel("二维码内容")
        placeholderStorage.addLayoutManager(placeholderLayout)
        placeholderLayout.addTextContainer(placeholderContainer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let font, let textContainer else { return }
        placeholderStorage.setAttributedString(NSAttributedString(
            string: "粘贴链接，或写下想分享的内容…",
            attributes: [.font: font, .foregroundColor: NSColor.placeholderTextColor]
        ))
        // Use the editor's text geometry so the placeholder shares its first line.
        placeholderContainer.containerSize = textContainer.containerSize
        placeholderContainer.lineFragmentPadding = textContainer.lineFragmentPadding
        placeholderLayout.drawGlyphs(
            forGlyphRange: placeholderLayout.glyphRange(for: placeholderContainer),
            at: textContainerOrigin
        )
    }
}
