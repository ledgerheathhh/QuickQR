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
}
