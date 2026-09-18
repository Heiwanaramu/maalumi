import Foundation
import SwiftUI

// MARK: - History Item

struct HistoryItem: Identifiable, Codable {
    let id: UUID
    let url: String
    let title: String
    let visitedAt: Date

    init(url: String, title: String) {
        self.id        = UUID()
        self.url       = url
        self.title     = title
        self.visitedAt = Date()
    }
}

// MARK: - History Manager

@MainActor
final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published private(set) var items: [HistoryItem] = []

    private let storageKey = "com.maalumi.history"
    private let maxItems   = 500

    private init() { load() }

    func record(url: String, title: String) {
        guard !url.isEmpty, url != "about:blank", url != "m:config" else { return }
        // Remove duplicates of the same URL (keep newest)
        items.removeAll { $0.url == url }
        items.insert(HistoryItem(url: url, title: title.isEmpty ? url : title), at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        save()
    }

    func clear() {
        items = []
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    // Group history by relative day label
    var groupedByDay: [(label: String, items: [HistoryItem])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        var groups: [String: [HistoryItem]] = [:]
        for item in items {
            let label: String
            if calendar.isDateInToday(item.visitedAt)     { label = "Today" }
            else if calendar.isDateInYesterday(item.visitedAt) { label = "Yesterday" }
            else { label = formatter.string(from: item.visitedAt) }
            groups[label, default: []].append(item)
        }

        // Sort groups newest-first
        let order = groups.keys.sorted { a, b in
            let aDate = groups[a]!.first!.visitedAt
            let bDate = groups[b]!.first!.visitedAt
            return aDate > bDate
        }
        return order.map { ($0, groups[$0]!) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = decoded
        }
    }
}
