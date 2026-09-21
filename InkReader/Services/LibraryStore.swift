import Foundation
import SwiftUI

/// 书架 + 全局阅读设置
final class LibraryStore: ObservableObject {
    @Published var books: [Book] = []
    @Published var settings: ReadingSettings = ReadingSettings() {
        didSet { saveSettings() }
    }
    @Published var sortOption: SortOption = .lastRead {
        didSet { UserDefaults.standard.set(sortOption.rawValue, forKey: "library.sort") }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case lastRead, addedAt, title, progress
        var id: String { rawValue }
        var title: String {
            switch self {
            case .lastRead: return "最近阅读"
            case .addedAt: return "添加时间"
            case .title: return "书名"
            case .progress: return "阅读进度"
            }
        }
    }

    init() {
        Storage.ensureDirectories()
        if let raw = UserDefaults.standard.string(forKey: "library.sort"),
           let option = SortOption(rawValue: raw) {
            sortOption = option
        }
        load()
    }

    // MARK: - 持久化

    func load() {
        if let data = try? Data(contentsOf: Storage.libraryFile),
           let decoded = try? JSONDecoder().decode([Book].self, from: data) {
            books = decoded
        }
        if let data = try? Data(contentsOf: Storage.settingsFile),
           let decoded = try? JSONDecoder().decode(ReadingSettings.self, from: data) {
            settings = decoded
        }
    }

    func save() {
        try? FileManager.default.createDirectory(
            at: Storage.documents, withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(books) {
            try? data.write(to: Storage.libraryFile, options: .atomic)
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: Storage.settingsFile, options: .atomic)
        }
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = self.settings.keepScreenOn
        }
    }

    // MARK: - 增删改

    func add(_ book: Book) {
        if let idx = books.firstIndex(where: { $0.id == book.id }) {
            books[idx] = book
        } else {
            books.insert(book, at: 0)
        }
        save()
    }

    func update(_ book: Book) {
        guard let idx = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[idx] = book
        save()
    }

    func delete(_ book: Book) {
        try? FileManager.default.removeItem(at: book.fileURL)
        if let cover = book.coverURL { try? FileManager.default.removeItem(at: cover) }
        try? FileManager.default.removeItem(
            at: Storage.annotationsDirectory.appendingPathComponent(book.id.uuidString)
        )
        try? FileManager.default.removeItem(
            at: Storage.comicCacheDirectory.appendingPathComponent(book.id.uuidString)
        )
        books.removeAll { $0.id == book.id }
        save()
    }

    func book(withId id: UUID) -> Book? {
        books.first { $0.id == id }
    }

    // MARK: - 收藏夹归属

    /// 把一批书加进收藏夹（已经在里面的不会重复加）
    func add(_ bookIds: Set<UUID>, toCollection collectionId: UUID) {
        guard !bookIds.isEmpty else { return }
        var changed = false
        for idx in books.indices where bookIds.contains(books[idx].id) {
            if !books[idx].collectionIds.contains(collectionId) {
                books[idx].collectionIds.append(collectionId)
                changed = true
            }
        }
        if changed { save() }
    }

    func remove(_ bookIds: Set<UUID>, fromCollection collectionId: UUID) {
        guard !bookIds.isEmpty else { return }
        var changed = false
        for idx in books.indices where bookIds.contains(books[idx].id) {
            if let at = books[idx].collectionIds.firstIndex(of: collectionId) {
                books[idx].collectionIds.remove(at: at)
                changed = true
            }
        }
        if changed { save() }
    }

    /// 收藏夹被删掉后，把书上的引用摘干净，别留下指向不存在的 id
    func pruneCollectionReferences(_ removedIds: Set<UUID>) {
        guard !removedIds.isEmpty else { return }
        var changed = false
        for idx in books.indices {
            let before = books[idx].collectionIds.count
            books[idx].collectionIds.removeAll { removedIds.contains($0) }
            if books[idx].collectionIds.count != before { changed = true }
        }
        if changed { save() }
    }

    func books(inCollection collectionId: UUID) -> [Book] {
        books.filter { $0.collectionIds.contains(collectionId) }
    }

    // MARK: - 封面

    func setCover(mode: BookCoverMode?, colorHex: String?, for id: UUID) {
        guard let idx = books.firstIndex(where: { $0.id == id }) else { return }
        books[idx].coverMode = mode
        books[idx].coverColorHex = colorHex
        save()
    }

    // MARK: - 排序 / 搜索

    func sortedBooks(keyword: String) -> [Book] {
        var result = books
        if !keyword.trimmed.isEmpty {
            let kw = keyword.trimmed.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(kw) || $0.author.lowercased().contains(kw)
            }
        }
        switch sortOption {
        case .lastRead:
            result.sort { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
        case .addedAt:
            result.sort { $0.addedAt > $1.addedAt }
        case .title:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .progress:
            result.sort { $0.progress > $1.progress }
        }
        return result
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
