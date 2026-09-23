//  墨阅 InkReader · InkReader/Services/ComicPageStore.swift
//  功能：漫画页序 —— 自定义排序、删页、从某页拆开、合入另一本；合并与拆分会重写 cbz 并重映射标注。
//  要点：页序存「压缩包内相对路径」，Caches 被清后重解压仍然对得上。

import Foundation
import ZIPFoundation

/// 漫画的页面顺序 / 合并 / 拆分
///
/// 页序存的是「压缩包里的相对路径」而不是绝对地址：
/// 系统清掉 Caches 之后会重新解压，相对路径还是原来那几个，照样对得上。
final class ComicPageStore: ObservableObject {
    /// bookId -> 有序的相对路径
    @Published private(set) var orders: [UUID: [String]] = [:]

    private struct Persisted: Codable {
        var orders: [String: [String]]
    }

    private static var file: URL {
        Storage.documents.appendingPathComponent("comicpages.json")
    }

    init() {
        load()
    }

    // MARK: 持久化

    func load() {
        guard let data = try? Data(contentsOf: Self.file),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        var mapped: [UUID: [String]] = [:]
        for (key, value) in decoded.orders {
            if let id = UUID(uuidString: key) { mapped[id] = value }
        }
        orders = mapped
    }

    func save() {
        var flat: [String: [String]] = [:]
        for (key, value) in orders { flat[key.uuidString] = value }
        guard let data = try? JSONEncoder().encode(Persisted(orders: flat)) else { return }
        try? data.write(to: Self.file, options: .atomic)
    }

    // MARK: 读取

    func cacheDirectory(for book: Book) -> URL {
        Storage.comicCacheDirectory.appendingPathComponent(book.id.uuidString, isDirectory: true)
    }

    /// 按当前顺序返回这一本的页面文件
    func pages(for book: Book) -> [URL] {
        guard let images = try? ComicExtractor.extractImages(for: book),
              !images.isEmpty else { return [] }
        let base = cacheDirectory(for: book)
        if let stored = orders[book.id], stored.count == images.count {
            var lookup: [String: URL] = [:]
            for url in images { lookup[relativePath(of: url, from: base)] = url }
            let mapped = stored.compactMap { lookup[$0] }
            if mapped.count == images.count { return mapped }
        }
        return images
    }

    func relativePaths(for book: Book) -> [String] {
        let base = cacheDirectory(for: book)
        return pages(for: book).map { relativePath(of: $0, from: base) }
    }

    func relativePath(of url: URL, from base: URL) -> String {
        let full = url.standardizedFileURL.path
        let root = base.standardizedFileURL.path
        if full.hasPrefix(root) {
            var rest = String(full.dropFirst(root.count))
            while rest.hasPrefix("/") { rest.removeFirst() }
            return rest
        }
        return url.lastPathComponent
    }

    // MARK: 编辑顺序

    func setOrder(_ paths: [String], for bookId: UUID) {
        orders[bookId] = paths
        save()
    }

    func move(bookId: UUID, from source: IndexSet, to destination: Int) {
        guard var list = orders[bookId] else { return }
        list.move(fromOffsets: source, toOffset: destination)
        orders[bookId] = list
        save()
    }

    /// 删页：页面号会整体前移，调用方要顺手把标注搬一下
    func removePages(bookId: UUID, at offsets: IndexSet) -> [Int: Int] {
        guard var list = orders[bookId] else { return [:] }
        var removed: [Int] = []
        for offset in offsets.sorted() where offset < list.count { removed.append(offset) }
        list.remove(atOffsets: offsets)
        orders[bookId] = list
        save()

        // 旧页号 → 新页号
        var mapping: [Int: Int] = [:]
        var shift = 0
        let dropped = Set(removed)
        for page in 0..<(list.count + removed.count) {
            if dropped.contains(page) {
                shift += 1
                continue
            }
            mapping[page] = page - shift
        }
        return mapping
    }

    /// 页面重排（手动排序之后用）
    func mapping(from oldPaths: [String], to newPaths: [String]) -> [Int: Int] {
        var mapping: [Int: Int] = [:]
        for (newIndex, path) in newPaths.enumerated() {
            if let oldIndex = oldPaths.firstIndex(of: path) {
                mapping[oldIndex] = newIndex
            }
        }
        return mapping
    }

    func resetOrder(bookId: UUID) {
        orders.removeValue(forKey: bookId)
        save()
    }

    func clear(bookId: UUID) {
        orders.removeValue(forKey: bookId)
        save()
    }

    // MARK: 合并 / 拆分

    /// 把 source 整本接到 target 后面，source 随后从书架移除
    /// （source 上的书签 / 笔记 / 涂鸦按页号平移到 target 上，不删）
    @discardableResult
    func merge(_ source: Book,
               into target: Book,
               library: LibraryStore,
               annotations: AnnotationStore) throws -> Book {
        let targetPages = pages(for: target)
        let sourcePages = pages(for: source)
        guard !sourcePages.isEmpty else { throw ImportError.noImages }
        guard source.id != target.id else { throw ImportError.readFailed }

        let fileName = try writeArchive(pages: targetPages + sourcePages)
        let oldFile = target.fileURL

        var merged = target
        merged.fileName = fileName
        merged.totalPages = targetPages.count + sourcePages.count
        merged.fileSize = Storage.fileSize(
            at: Storage.booksDirectory.appendingPathComponent(fileName)
        )

        // 旧页号 → 新页号：source 的第 p 页变成第 targetPages.count + p 页
        var mapping: [Int: Int] = [:]
        for page in 0..<sourcePages.count { mapping[page] = targetPages.count + page }
        annotations.remapPages(bookId: source.id, mapping: mapping, to: target.id)

        // 顺序要重来：新压缩包里的名字是重新编号的
        resetOrder(bookId: target.id)
        clear(bookId: source.id)
        resetCache(target.id)
        resetCache(source.id)

        try? FileManager.default.removeItem(at: oldFile)
        library.update(merged)
        library.delete(source)
        return merged
    }

    /// 从第 index 页切开，后半截单独成一本新书
    @discardableResult
    func split(_ book: Book,
               at index: Int,
               library: LibraryStore,
               annotations: AnnotationStore) throws -> Book {
        let pages = self.pages(for: book)
        guard index > 0, index < pages.count else { throw ImportError.readFailed }

        let head = Array(pages[0..<index])
        let tail = Array(pages[index...])

        let headFile = try writeArchive(pages: head)
        let tailFile = try writeArchive(pages: tail)

        let newId = UUID()
        var tailBook = Book(
            id: newId,
            title: "\(book.title)（第 \(index + 1)-\(pages.count) 页）",
            format: .comic,
            fileName: tailFile,
            fileSize: Storage.fileSize(
                at: Storage.booksDirectory.appendingPathComponent(tailFile)
            )
        )
        tailBook.totalPages = tail.count
        tailBook.locator = "0"

        var headBook = book
        headBook.fileName = headFile
        headBook.totalPages = head.count
        headBook.locator = String(min(max(0, Int(book.locator) ?? 0), head.count - 1))
        headBook.fileSize = Storage.fileSize(
            at: Storage.booksDirectory.appendingPathComponent(headFile)
        )

        // 后半截的标注搬到新书，页号减掉 index
        var mapping: [Int: Int] = [:]
        for page in index..<pages.count { mapping[page] = page - index }
        annotations.remapPages(bookId: book.id, mapping: mapping, to: newId)

        resetOrder(bookId: book.id)
        resetOrder(bookId: newId)
        resetCache(book.id)
        resetCache(newId)

        if let coverURL = book.coverURL,
           let data = try? Data(contentsOf: coverURL) {
            let name = "\(newId.uuidString).png"
            try? data.write(to: Storage.coversDirectory.appendingPathComponent(name))
            tailBook.coverFileName = name
        }

        try? FileManager.default.removeItem(at: book.fileURL)
        library.update(headBook)
        library.add(tailBook)
        return tailBook
    }

    // MARK: 内部

    /// 重新打包成一个 cbz：页名按 %06d 编号，解压回来就是这个顺序
    private func writeArchive(pages: [URL]) throws -> String {
        let fileName = "\(UUID().uuidString).cbz"
        let target = Storage.booksDirectory.appendingPathComponent(fileName)
        guard let archive = Archive(url: target, accessMode: .create) else {
            throw ImportError.readFailed
        }
        for (index, url) in pages.enumerated() {
            let name = String(format: "%06d.%@", index, url.pathExtension.lowercased())
            try? archive.addEntry(with: name, fileURL: url)
        }
        return fileName
    }

    private func resetCache(_ bookId: UUID) {
        let dir = Storage.comicCacheDirectory.appendingPathComponent(bookId.uuidString)
        try? FileManager.default.removeItem(at: dir)
    }
}
