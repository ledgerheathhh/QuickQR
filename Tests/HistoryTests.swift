import XCTest

final class HistoryTests: XCTestCase {
    @MainActor
    func testRecordsUniqueRecentEntriesAndPersistsThem() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = QRHistoryStore(defaults: defaults, limit: 2)

        store.record("first", at: Date(timeIntervalSince1970: 1))
        store.record("second", at: Date(timeIntervalSince1970: 2))
        store.record("first", at: Date(timeIntervalSince1970: 3))
        store.record("third", at: Date(timeIntervalSince1970: 4))

        XCTAssertEqual(store.entries.map(\.text), ["third", "first"])
        XCTAssertEqual(store.entries.last?.createdAt, Date(timeIntervalSince1970: 3))
        XCTAssertEqual(
            QRHistoryStore(defaults: defaults, limit: 2).entries,
            store.entries
        )
    }

    @MainActor
    func testIgnoresBlankInputAndSupportsRemoval() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = QRHistoryStore(defaults: defaults)

        store.record(" \n\t")
        XCTAssertTrue(store.entries.isEmpty)

        store.record("one")
        store.record("two")
        store.remove(try XCTUnwrap(store.entries.last))
        XCTAssertEqual(store.entries.map(\.text), ["two"])

        store.removeAll()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(QRHistoryStore(defaults: defaults).entries.isEmpty)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "QuickQRTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    @MainActor
    func testUndoRemovalPreservesOrderAndPersistenceWithoutDuplicates() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = QRHistoryStore(defaults: defaults, limit: 3)
        store.record("one", at: Date(timeIntervalSince1970: 1))
        store.record("two", at: Date(timeIntervalSince1970: 2))
        store.record("three", at: Date(timeIntervalSince1970: 3))
        store.remove(try XCTUnwrap(store.entries.first { $0.text == "two" }))
        store.record("four", at: Date(timeIntervalSince1970: 4))
        store.undoRemoval()
        XCTAssertEqual(store.entries.map(\.text), ["four", "three", "two"])
        XCTAssertEqual(QRHistoryStore(defaults: defaults, limit: 3).entries, store.entries)

        store.remove(try XCTUnwrap(store.entries.last))
        store.record("two", at: Date(timeIntervalSince1970: 5))
        store.undoRemoval()
        XCTAssertEqual(store.entries.map(\.text), ["two", "four", "three"])
        store.remove(try XCTUnwrap(store.entries.first))
        store.removeAll()
        store.undoRemoval()
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testSearchMatchesTextAndLinksWithoutChangingHistory() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = QRHistoryStore(defaults: defaults)
        let url = "https://Example.com/你好?token=ABC#section"
        store.record("你好 QuickQR", at: Date(timeIntervalSince1970: 1))
        store.record(url, at: Date(timeIntervalSince1970: 2))
        store.record("其他内容", at: Date(timeIntervalSince1970: 3))
        let original = store.entries

        XCTAssertEqual(store.entries(matching: "你好").map(\.text), [url, "你好 QuickQR"])
        XCTAssertEqual(store.entries(matching: "  EXAMPLE.COM\n").map(\.text), [url])
        XCTAssertEqual(store.entries(matching: "token=abc").map(\.text), [url])
        XCTAssertEqual(store.entries(matching: "quickqr").map(\.text), ["你好 QuickQR"])
        XCTAssertTrue(store.entries(matching: "不存在").isEmpty)
        XCTAssertEqual(store.entries(matching: ""), original)
        XCTAssertEqual(store.entries(matching: " \n\t"), original)
        XCTAssertEqual(store.entries, original)
        XCTAssertEqual(QRHistoryStore(defaults: defaults).entries, original)

        store.remove(try XCTUnwrap(store.entries(matching: "token").first))
        XCTAssertTrue(store.entries(matching: "token").isEmpty)
        store.undoRemoval()
        XCTAssertEqual(store.entries(matching: "token").map(\.text), [url])
    }

    func testTimeLabelsShowFixedDateAndMinuteAndLinksKeepOriginalContent() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026, month: 10, day: 29, hour: 14, minute: 5, second: 10
        )))
        let url = "https://example.com/你好?token=123#section"
        let entry = QRHistoryEntry(id: UUID(), text: url, createdAt: date)
        XCTAssertEqual(entry.linkHost, "example.com")
        XCTAssertEqual(entry.text, url)
        XCTAssertTrue(entry.timeLabel.contains("2026"))
        XCTAssertTrue(entry.timeLabel.contains("10"))
        XCTAssertTrue(entry.timeLabel.contains("29"))
        XCTAssertTrue(entry.timeLabel.contains("14:05"))
        XCTAssertEqual(entry.timeLabel.filter { $0 == ":" }.count, 1)
        let sameMinute = QRHistoryEntry(id: UUID(), text: "", createdAt: date.addingTimeInterval(40))
        XCTAssertEqual(entry.timeLabel, sameMinute.timeLabel)
        let older = QRHistoryEntry(id: UUID(), text: "普通文字", createdAt: date.addingTimeInterval(-300))
        XCTAssertNil(older.linkHost)
        XCTAssertTrue(older.timeLabel.contains("14:00"))
    }
}
