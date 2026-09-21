//  墨阅 InkReader · InkReader/Services/LibraryStore.swift
//  功能：书架仓库 —— 书籍增删改、排序（置顶优先）、重命名、置顶、清除全部数据。
//  要点：sortedBooks 先把 pinnedAt 非空的排在前面，再套用排序选项。

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

    // MARK: - 置顶 / 重命名

    func togglePin(_ id: UUID) {
        guard let idx = books.firstIndex(where: { $0.id == id }) else { return }
        books[idx].pinnedAt = books[idx].pinnedAt == nil ? Date() : nil
        save()
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmed
        guard !trimmed.isEmpty else { return }
        guard let idx = books.firstIndex(where: { $0.id == id }) else { return }
        books[idx].title = trimmed
        save()
    }

    // MARK: - 清空数据 / 卸载
    //
    // iOS 里「卸载 App」系统是自带会把数据一起带走的，所以在 App 内只提供
    // 「清除数据」这一档：把书、笔记、涂鸦、收藏夹、修订记录全部抹掉，
    // App 本身还留在 iPad 上，等于恢复出厂的书架。

    func clearAllData(annotations: AnnotationStore,
                      collections: CollectionStore,
                      revisions: RevisionStore) {
        for book in books {
            try? FileManager.default.removeItem(at: book.fileURL)
            if let cover = book.coverURL { try? FileManager.default.removeItem(at: cover) }
            try? FileManager.default.removeItem(
                at: Storage.comicCacheDirectory.appendingPathComponent(book.id.uuidString)
            )
        }
        try? FileManager.default.removeItem(at: Storage.drawingsDirectory)

        let targets: [URL] = [
            Storage.libraryFile,
            Storage.annotationsFile,
            Storage.collectionsFile,
            Storage.documents.appendingPathComponent("revisions.json"),
            Storage.documents.appendingPathComponent("comicpages.json")
        ]
        for url in targets { try? FileManager.default.removeItem(at: url) }

        books = []
        annotations.bookmarks = []
        annotations.notes = []
        annotations.highlights = []
        annotations.save()
        collections.collections = []
        collections.save()
        revisions.reset()
        save()
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
        // 置顶的书永远在最前，其余按选的排序规则走
        result.sort { lhs, rhs in
            if (lhs.pinnedAt != nil) != (rhs.pinnedAt != nil) {
                return lhs.pinnedAt != nil
            }
            if lhs.pinnedAt != nil, rhs.pinnedAt != nil {
                return (lhs.pinnedAt ?? .distantPast) > (rhs.pinnedAt ?? .distantPast)
            }
            switch sortOption {
            case .lastRead:
                return (lhs.lastReadAt ?? .distantPast) > (rhs.lastReadAt ?? .distantPast)
            case .addedAt:
                return lhs.addedAt > rhs.addedAt
            case .title:
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            case .progress:
                return lhs.progress > rhs.progress
            }
        }
        return result
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
