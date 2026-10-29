import Combine
import Foundation

struct QRHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    var createdAt: Date

    var linkHost: String? {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return url.host
    }

    var timeLabel: String {
        createdAt.formatted(
            .dateTime.locale(Locale(identifier: "zh_CN"))
                .year().month(.twoDigits).day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        )
    }
}

@MainActor
final class QRHistoryStore: ObservableObject {
    static let maximumEntries = 20

    @Published private(set) var entries: [QRHistoryEntry]
    @Published private(set) var recentlyRemoved: QRHistoryEntry?

    private let defaults: UserDefaults
    private let storageKey: String
    private let limit: Int

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "quickQRHistory",
        limit: Int = 20
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.limit = limit
        let stored = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([QRHistoryEntry].self, from: $0) } ?? []
        entries = Array(stored.prefix(limit))
    }

    func entries(matching query: String) -> [QRHistoryEntry] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return entries }
        return entries.filter { $0.text.localizedStandardContains(keyword) }
    }

    func record(_ text: String, at date: Date = Date()) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let entry: QRHistoryEntry
        if let index = entries.firstIndex(where: { $0.text == text }) {
            entry = QRHistoryEntry(id: entries[index].id, text: text, createdAt: date)
            entries.remove(at: index)
        } else {
            entry = QRHistoryEntry(id: UUID(), text: text, createdAt: date)
        }
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        persist()
    }

    func remove(_ entry: QRHistoryEntry) {
        recentlyRemoved = entries.first { $0.id == entry.id }
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func undoRemoval() {
        guard let entry = recentlyRemoved else { return }
        recentlyRemoved = nil
        guard !entries.contains(where: { $0.text == entry.text }) else { return }
        let index = entries.firstIndex { $0.createdAt < entry.createdAt } ?? entries.endIndex
        entries.insert(entry, at: index)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        persist()
    }

    func discardRemoval() { recentlyRemoved = nil }

    func removeAll() {
        recentlyRemoved = nil
        entries.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
