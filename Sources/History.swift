import Combine
import Foundation

struct QRHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    var createdAt: Date
}

@MainActor
final class QRHistoryStore: ObservableObject {
    static let maximumEntries = 20

    @Published private(set) var entries: [QRHistoryEntry]

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
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func removeAll() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
