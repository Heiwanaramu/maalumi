import Foundation
import SwiftUI

// MARK: - Bookmark

struct Bookmark: Identifiable, Codable {
    let id: UUID
    var url: String
    var title: String
    var createdAt: Date

    init(url: String, title: String) {
        self.id        = UUID()
        self.url       = url
        self.title     = title.isEmpty ? url : title
        self.createdAt = Date()
    }
}

// MARK: - Bookmark Manager

@MainActor
final class BookmarkManager: ObservableObject {
    static let shared = BookmarkManager()

    @Published private(set) var bookmarks: [Bookmark] = []

    private let storageKey = "com.maalumi.bookmarks"

    private init() { load() }

    var isEmpty: Bool { bookmarks.isEmpty }

    func isBookmarked(url: String) -> Bool {
        bookmarks.contains { $0.url == url }
    }

    func toggle(url: String, title: String) {
        if let idx = bookmarks.firstIndex(where: { $0.url == url }) {
            bookmarks.remove(at: idx)
        } else {
            bookmarks.insert(Bookmark(url: url, title: title), at: 0)
        }
        save()
    }

    func add(url: String, title: String) {
        guard !isBookmarked(url: url) else { return }
        bookmarks.insert(Bookmark(url: url, title: title), at: 0)
        save()
    }

    func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    func rename(id: UUID, title: String) {
        if let idx = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks[idx].title = title
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = decoded
        }
    }
}
