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

    func testChineseTimeLabelsAndLinkHostKeepOriginalContent() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let url = "https://example.com/你好?token=123#section"
        let entry = QRHistoryEntry(id: UUID(), text: url, createdAt: now.addingTimeInterval(-10))
        XCTAssertEqual(entry.linkHost, "example.com")
        XCTAssertEqual(entry.text, url)
        XCTAssertEqual(entry.timeLabel(relativeTo: now), "刚刚")
        let older = QRHistoryEntry(id: UUID(), text: "普通文字", createdAt: now.addingTimeInterval(-300))
        XCTAssertNil(older.linkHost)
        XCTAssertEqual(older.timeLabel(relativeTo: now), "5 分钟前")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(QRHistoryEntry(id: UUID(), text: "", createdAt: yesterday).timeLabel(relativeTo: now).hasPrefix("昨天 "))
    }
}
