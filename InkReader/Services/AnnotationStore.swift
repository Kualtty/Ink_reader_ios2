import Foundation
import PencilKit
import SwiftUI

/// 书签 / 笔记 / 高亮 / 手写涂鸦 的统一仓库
final class AnnotationStore: ObservableObject {
    @Published var bookmarks: [Bookmark] = []
    @Published var notes: [Note] = []
    @Published var highlights: [HighlightRange] = []

    /// 内存缓存：key = "<bookId>|<anchor>"
    private var drawingCache: [String: PKDrawing] = [:]

    private struct Persisted: Codable {
        var bookmarks: [Bookmark]
        var notes: [Note]
        var highlights: [HighlightRange]
    }

    init() {
        Storage.ensureDirectories()
        load()
    }

    // MARK: - 持久化

    func load() {
        guard let data = try? Data(contentsOf: Storage.annotationsFile),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        bookmarks = decoded.bookmarks
        notes = decoded.notes
        highlights = decoded.highlights
    }

    func save() {
        let payload = Persisted(bookmarks: bookmarks, notes: notes, highlights: highlights)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: Storage.annotationsFile, options: .atomic)
    }

    // MARK: - 书签

    func bookmarks(for bookId: UUID) -> [Bookmark] {
        bookmarks.filter { $0.bookId == bookId }.sorted { $0.page < $1.page }
    }

    func isBookmarked(bookId: UUID, locator: String) -> Bool {
        bookmarks.contains { $0.bookId == bookId && $0.locator == locator }
    }

    func toggleBookmark(bookId: UUID, page: Int, locator: String, excerpt: String) {
        if let index = bookmarks.firstIndex(where: { $0.bookId == bookId && $0.locator == locator }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.append(Bookmark(bookId: bookId, page: page, locator: locator, excerpt: excerpt))
        }
        save()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        save()
    }

    // MARK: - 笔记

    func notes(for bookId: UUID) -> [Note] {
        notes.filter { $0.bookId == bookId }.sorted { $0.page < $1.page }
    }

    func add(_ note: Note) {
        notes.append(note)
        save()
    }

    func update(_ note: Note) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var copy = note
        copy.updatedAt = Date()
        notes[idx] = copy
        save()
    }

    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        highlights.removeAll { $0.noteId == note.id }
        save()
    }

    // MARK: - 高亮

    func highlights(for bookId: UUID) -> [HighlightRange] {
        highlights.filter { $0.bookId == bookId }.sorted { $0.start < $1.start }
    }

    func addHighlight(_ highlight: HighlightRange) {
        highlights.append(highlight)
        save()
    }

    /// 删除与给定范围重叠的高亮
    func removeHighlights(bookId: UUID, overlapping range: NSRange) {
        highlights.removeAll {
            $0.bookId == bookId && NSIntersectionRange($0.range, range).length > 0
        }
        save()
    }

    func deleteHighlight(_ highlight: HighlightRange) {
        highlights.removeAll { $0.id == highlight.id }
        save()
    }

    // MARK: - 手写涂鸦

    private func cacheKey(_ bookId: UUID, _ anchor: String) -> String {
        "\(bookId.uuidString)|\(anchor)"
    }

    func drawing(for bookId: UUID, anchor: String) -> PKDrawing {
        let key = cacheKey(bookId, anchor)
        if let cached = drawingCache[key] { return cached }
        let url = Storage.drawingURL(bookId: bookId, key: anchor)
        if let data = try? Data(contentsOf: url),
           let drawing = try? PKDrawing(data: data) {
            drawingCache[key] = drawing
            return drawing
        }
        return PKDrawing()
    }

    func setDrawing(_ drawing: PKDrawing, for bookId: UUID, anchor: String) {
        let key = cacheKey(bookId, anchor)
        drawingCache[key] = drawing
        let url = Storage.drawingURL(bookId: bookId, key: anchor)
        let data = drawing.dataRepresentation()
        try? data.write(to: url, options: .atomic)
        objectWillChange.send()
    }

    func hasDrawing(bookId: UUID, anchor: String) -> Bool {
        let key = cacheKey(bookId, anchor)
        if let cached = drawingCache[key] { return !cached.bounds.isEmpty }
        return FileManager.default.fileExists(
            atPath: Storage.drawingURL(bookId: bookId, key: anchor).path
        )
    }

    func deleteDrawing(bookId: UUID, anchor: String) {
        let key = cacheKey(bookId, anchor)
        drawingCache.removeValue(forKey: key)
        try? FileManager.default.removeItem(
            at: Storage.drawingURL(bookId: bookId, key: anchor)
        )
        objectWillChange.send()
    }

    /// 某本书所有有涂鸦的位置锚点
    func drawingAnchors(for bookId: UUID) -> [String] {
        let dir = Storage.drawingsDirectory(for: bookId)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files
            .filter { $0.hasSuffix(".drawing") }
            .map { $0.replacingOccurrences(of: ".drawing", with: "") }
            .sorted()
    }
}
