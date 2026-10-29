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
        XCTAssertTrue(model.isFocused)
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
        refresh(host)
        XCTAssertFalse(model.isFocused)
        model.text = "  \"粘贴👋\"\n第二行  "
        model.focusRequest += 1
        refresh(host)
        XCTAssertEqual(textView.string, model.text)
        XCTAssertEqual(textView.selectedRange().location, (model.text as NSString).length)
        XCTAssertTrue(window.firstResponder === textView)
        XCTAssertTrue(model.isFocused)

        model.text = ""
        model.focusRequest += 1
        refresh(host)
        XCTAssertEqual(textView.string, "")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertTrue(window.firstResponder === textView)
    }

    @MainActor
    func testExternalClearAndReplacementCanBeUndoneAndRedone() throws {
        let (_, host, model, textView) = try makeInput()
        let original = "原始链接 👋\n第二行"
        textView.insertText(original, replacementRange: NSRange(location: NSNotFound, length: 0))
        refresh(host)
        let undo = try XCTUnwrap(textView.undoManager)

        model.text = ""
        refresh(host)
        undo.undo()
        refresh(host)
        XCTAssertEqual(model.text, original)
        XCTAssertEqual(textView.string, original)
        undo.redo()
        refresh(host)
        XCTAssertEqual(model.text, "")

        undo.undo()
        refresh(host)
        model.text = "替换后的文字"
        refresh(host)
        undo.undo()
        refresh(host)
        XCTAssertEqual(model.text, original)
        XCTAssertEqual(textView.string, original)
        undo.redo()
        refresh(host)
        XCTAssertEqual(model.text, "替换后的文字")
    }

    @MainActor
    func testMarkedTextSurvivesSwiftUIUpdate() throws {
        let (window, host, model, textView) = try makeInput()
        textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                               replacementRange: NSRange(location: NSNotFound, length: 0))
        refresh(host)
        XCTAssertTrue(textView.hasMarkedText())
        // Publishing anything re-evaluates the body and so runs updateNSView, which is
        // what a freshly generated code does in the app. Without this the assertions
        // below would hold for the wrong reason: updateNSView is never called at all.
        model.focusRequest += 1
        refresh(host)
        XCTAssertTrue(textView.hasMarkedText(), "Composition must survive a SwiftUI update")
        XCTAssertEqual(textView.string, "ni")
        textView.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0))
        refresh(host)
        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertEqual(model.text, "你")
        XCTAssertTrue(window.firstResponder === textView)
    }

    @MainActor
    func testExternalChangeStillAppliesDuringComposition() throws {
        let (_, host, model, textView) = try makeInput()
        textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                               replacementRange: NSRange(location: NSNotFound, length: 0))
        refresh(host)
        XCTAssertTrue(textView.hasMarkedText())
        model.text = "粘贴的内容"
        refresh(host)
        XCTAssertEqual(textView.string, "粘贴的内容", "An external change must still reach the editor")
        XCTAssertEqual(textView.selectedRange().location, ("粘贴的内容" as NSString).length)
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
    @Published var isFocused = false
}

private struct InputHarness: View {
    @ObservedObject var model: InputModel

    var body: some View {
        TextInput(text: $model.text, focusRequest: model.focusRequest, isFocused: $model.isFocused)
            .frame(width: 324, height: 96)
    }
}
