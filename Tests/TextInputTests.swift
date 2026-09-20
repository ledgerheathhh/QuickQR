import AppKit
import SwiftUI
import XCTest

final class TextInputTests: XCTestCase {
    @MainActor
    func testPlaceholderMatchesEnteredText() throws {
        _ = NSApplication.shared
        for width in [324.0, 180.0] {
            let textView = QRTextView()
            textView.frame = NSRect(x: 0, y: 0, width: width, height: 96)
            let placeholder = try pixels(of: textView)
            XCTAssertTrue(placeholder.contains { $0 != 0 }, "Placeholder must actually be drawn")
            textView.string = "粘贴链接，或写下想分享的内容…"
            textView.textColor = .placeholderTextColor
            let enteredText = try pixels(of: textView)
            XCTAssertEqual(placeholder, enteredText, "Placeholder must match native text layout at width \(width)")
        }
    }

    @MainActor
    func testInputSynchronizationSelectionAndFocus() throws {
        let (window, host, model, textView) = try makeInput()
        XCTAssertFalse(textView.isAutomaticQuoteSubstitutionEnabled)
        let input = "\"hello\" 'world' 中文“原样保留”\n👋"
        for character in input {
            textView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        XCTAssertEqual(textView.string, input)
        XCTAssertEqual(model.text, input)
        refresh(host)
        textView.breakUndoCoalescing()
        textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        textView.breakUndoCoalescing()
        refresh(host)
        try XCTUnwrap(textView.undoManager).undo()
        XCTAssertEqual(textView.string, input)
        XCTAssertEqual(model.text, input)
        textView.setSelectedRange(NSRange(location: 2, length: 3))
        refresh(host)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 3))

        window.makeFirstResponder(nil)
        model.text = "  \"粘贴👋\"\n第二行  "
        model.focusRequest += 1
        refresh(host)
        XCTAssertEqual(textView.string, model.text)
        XCTAssertEqual(textView.selectedRange().location, (model.text as NSString).length)
        XCTAssertTrue(window.firstResponder === textView)

        model.text = ""
        model.focusRequest += 1
        refresh(host)
        XCTAssertEqual(textView.string, "")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertTrue(window.firstResponder === textView)
    }

    @MainActor
    func testMarkedTextSurvivesSwiftUIUpdate() throws {
        let (window, host, model, textView) = try makeInput()
        textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                               replacementRange: NSRange(location: NSNotFound, length: 0))
        refresh(host)
        XCTAssertTrue(textView.hasMarkedText())
        textView.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0))
        refresh(host)
        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertEqual(model.text, "你")
        XCTAssertTrue(window.firstResponder === textView)
    }

    @MainActor
    private func pixels(of view: NSView) throws -> Data {
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.bitmapData)
        return Data(bytes: data, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    @MainActor
    private func makeInput() throws -> (NSWindow, NSView, InputModel, QRTextView) {
        _ = NSApplication.shared
        let model = InputModel()
        let host = NSHostingView(rootView: InputHarness(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 324, height: 96),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        refresh(host)
        func findTextView(_ view: NSView) -> QRTextView? {
            if let textView = view as? QRTextView { return textView }
            return view.subviews.lazy.compactMap(findTextView).first
        }
        return (window, host, model, try XCTUnwrap(findTextView(host)))
    }

    @MainActor
    private func refresh(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        view.layoutSubtreeIfNeeded()
    }
}

private final class InputModel: ObservableObject {
    @Published var text = ""
    @Published var focusRequest = 0
}

private struct InputHarness: View {
    @ObservedObject var model: InputModel

    var body: some View {
        TextInput(text: $model.text, focusRequest: model.focusRequest)
            .frame(width: 324, height: 96)
    }
}
