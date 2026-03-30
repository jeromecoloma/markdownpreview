import Foundation

@MainActor
final class RecentFilesViewModel: ObservableObject {
    @Published private(set) var recentFiles: [RecentFile] = []

    private let defaults = UserDefaults.standard
    private let storageKey = "MarkdownPreview.recentFiles.v1"
    private let maxRecentFiles = 20

    init() {
        load()
    }

    func add(url: URL) {
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        let standardizedURL = url.standardizedFileURL
        var items = recentFiles
        let existingIndex = items.firstIndex { existing in
            guard let existingURL = resolveURL(for: existing, refreshIfNeeded: false) else {
                return false
            }
            return existingURL.standardizedFileURL == standardizedURL
        }

        let preservedID = existingIndex.map { items[$0].id }

        if let existingIndex {
            items.remove(at: existingIndex)
        }

        let item = RecentFile(
            id: preservedID ?? UUID().uuidString,
            fileName: url.lastPathComponent,
            parentDirectory: url.deletingLastPathComponent().path,
            bookmarkData: bookmarkData
        )

        items.insert(item, at: 0)
        recentFiles = Array(items.prefix(maxRecentFiles))
        persist()
    }

    func resolveURL(for item: RecentFile, refreshIfNeeded: Bool = true) -> URL? {
        var isStale = false

        guard let url = try? URL(
            resolvingBookmarkData: item.bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if isStale, refreshIfNeeded {
            refreshBookmark(for: item, resolvedURL: url)
        }

        return url
    }

    func remove(_ item: RecentFile) {
        recentFiles.removeAll { $0.id == item.id }
        persist()
    }

    func item(withID id: String) -> RecentFile? {
        recentFiles.first { $0.id == id }
    }

    private func refreshBookmark(for item: RecentFile, resolvedURL: URL) {
        guard let updatedBookmark = try? resolvedURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        recentFiles = recentFiles.map { existing in
            guard existing.id == item.id else { return existing }
            return RecentFile(
                id: item.id,
                fileName: resolvedURL.lastPathComponent,
                parentDirectory: resolvedURL.deletingLastPathComponent().path,
                bookmarkData: updatedBookmark
            )
        }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }

        do {
            recentFiles = try JSONDecoder().decode([RecentFile].self, from: data)
        } catch {
            recentFiles = []
            defaults.removeObject(forKey: storageKey)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(recentFiles) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
