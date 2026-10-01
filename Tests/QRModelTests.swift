import AppKit
import XCTest

final class QRModelTests: XCTestCase {
    @MainActor
    func testCopyRecordsImmediatelyAndCannotExportPreviousInput() async throws {
        let (model, defaults, suite) = makeModel()
        defer { model.clear(); defaults.removePersistentDomain(forName: suite) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        model.text = "first"
        try await waitForResult(model)
        XCTAssertTrue(model.history.entries.isEmpty)
        model.copyImage(to: board)
        XCTAssertEqual(model.history.entries.map(\.text), ["first"])
        XCTAssertEqual(QRHistoryStore(defaults: defaults).entries.map(\.text), ["first"])
        XCTAssertEqual(board.data(forType: .png), Data("first".utf8))
        XCTAssertTrue(model.imageCopied)
        XCTAssertEqual(model.notice?.kind, .success)

        let changeCount = board.changeCount
        model.text = "second"
        XCTAssertNotNil(model.result, "Keep the old preview to avoid flickering")
        XCTAssertTrue(model.isGenerating)
        XCTAssertFalse(model.canExport)
        model.copyImage(to: board)
        XCTAssertEqual(board.changeCount, changeCount, "A stale result must not change the clipboard")
        try await waitForResult(model)
        XCTAssertEqual(model.result?.png, Data("second".utf8))
        model.copyImage(to: board)
        XCTAssertEqual(model.history.entries.map(\.text), ["second", "first"])
    }

    @MainActor
    func testAutomaticHistoryRecordsOnlyLatestStableInput() async throws {
        let (model, defaults, suite) = makeModel()
        defer { model.clear(); defaults.removePersistentDomain(forName: suite) }
        model.text = "intermediate"
        try await waitForResult(model)
        model.text = "final"
        try await waitForResult(model)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertEqual(model.history.entries.map(\.text), ["final"])
        XCTAssertEqual(QRHistoryStore(defaults: defaults).entries.map(\.text), ["final"])
    }

    @MainActor
    func testCopiedEntryIsNotAutomaticallyRecreatedAfterDeletion() async throws {
        let (model, defaults, suite) = makeModel()
        defer { model.clear(); defaults.removePersistentDomain(forName: suite) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        model.text = "copied"
        try await waitForResult(model)
        model.copyImage(to: board)
        model.removeHistory(try XCTUnwrap(model.history.entries.first))
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertTrue(model.history.entries.isEmpty)
        XCTAssertTrue(QRHistoryStore(defaults: defaults).entries.isEmpty)
        model.undoHistoryRemoval()
        XCTAssertEqual(model.history.entries.map(\.text), ["copied"])
    }

    @MainActor
    func testClearHistorySuppressesPendingRecordWithoutStoppingGeneration() async throws {
        let (model, defaults, suite) = makeModel()
        defer { model.clear(); defaults.removePersistentDomain(forName: suite) }
        model.text = "pending"
        model.clearHistory()
        try await waitForResult(model)
        XCTAssertTrue(model.canExport)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertTrue(model.history.entries.isEmpty)
        XCTAssertTrue(QRHistoryStore(defaults: defaults).entries.isEmpty)
        model.text = "next"
        try await waitForResult(model)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertEqual(model.history.entries.map(\.text), ["next"])
    }

    @MainActor
    func testSupersededGenerationCannotOverwriteNewResult() async throws {
        let (model, defaults, suite) = makeModel { text in
            if text == "slow" { Thread.sleep(forTimeInterval: 0.3) }
            return try Self.result(for: text)
        }
        defer { model.clear(); defaults.removePersistentDomain(forName: suite) }
        model.text = "slow"
        try await Task.sleep(nanoseconds: 200_000_000)
        model.text = "new"
        try await waitForResult(model)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(model.result?.png, Data("new".utf8))
        XCTAssertTrue(model.canExport)
        model.clear()
        XCTAssertNil(model.result)
        XCTAssertFalse(model.isGenerating)
        XCTAssertFalse(model.canExport)
        XCTAssertNil(model.error)
    }

    @MainActor
    func testOversizedInputAndGenerationFailureDisableExport() async throws {
        let (model, defaults, suite) = makeModel { text in
            if text == "failure" { throw QRCode.Failure.generation }
            return try Self.result(for: text)
        }
        defer { model.clear(); defaults.removePersistentDomain(forName: suite) }
        model.text = "valid"
        try await waitForResult(model)
        model.text = String(repeating: "中", count: 667)
        XCTAssertNil(model.result)
        XCTAssertFalse(model.canExport)
        XCTAssertFalse(model.isGenerating)
        XCTAssertNotNil(model.error)
        model.text = "failure"
        try await waitForResult(model)
        XCTAssertNil(model.result)
        XCTAssertFalse(model.canExport)
        XCTAssertEqual(model.error, QRCode.Failure.generation.errorDescription)
    }

    @MainActor
    func testSaveRecordsExportedSnapshotAndFailureDoesNotRecord() throws {
        let (model, defaults, suite) = makeModel()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            model.clear()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        model.text = "edited while saving"
        let url = directory.appendingPathComponent("code.png")
        let png = Data("exported snapshot".utf8)
        model.write(png, text: "original", to: url)
        XCTAssertEqual(try Data(contentsOf: url), png)
        XCTAssertEqual(model.history.entries.map(\.text), ["original"])
        XCTAssertEqual(model.notice?.kind, .success)
        model.write(png, text: "must not be recorded", to: directory)
        XCTAssertEqual(model.history.entries.map(\.text), ["original"])
        XCTAssertEqual(model.notice?.kind, .failure)
    }

    @MainActor
    func testDeleteCanBeUndoneAndNewNoticeDiscardsUndo() throws {
        let (model, defaults, suite) = makeModel()
        defer { model.clear(); defaults.removePersistentDomain(forName: suite) }
        model.history.record("one")
        model.removeHistory(try XCTUnwrap(model.history.entries.first))
        XCTAssertTrue(model.notice?.offersUndo == true)
        model.undoHistoryRemoval()
        XCTAssertEqual(model.history.entries.map(\.text), ["one"])
        XCTAssertFalse(model.notice?.offersUndo == true)
        model.removeHistory(try XCTUnwrap(model.history.entries.first))
        model.showNotice("warning", kind: .warning)
        XCTAssertNil(model.history.recentlyRemoved)
        model.undoHistoryRemoval()
        XCTAssertTrue(model.history.entries.isEmpty)
    }

    @MainActor
    private func waitForResult(_ model: QRModel) async throws {
        for _ in 0..<100 {
            if !model.isGenerating { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Generation did not finish")
    }

    @MainActor
    private func makeModel(
        generate: @escaping @Sendable (String) throws -> QRCode.Result = { try QRModelTests.result(for: $0) }
    ) -> (QRModel, UserDefaults, String) {
        let suite = "QuickQRModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let model = QRModel(history: QRHistoryStore(defaults: defaults), generateCode: generate)
        return (model, defaults, suite)
    }

    private static func result(for text: String) throws -> QRCode.Result {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return QRCode.Result(cgImage: try XCTUnwrap(context.makeImage()), png: Data(text.utf8))
    }
}
