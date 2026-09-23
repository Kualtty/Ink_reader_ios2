//  墨阅 InkReader · InkReader/Services/BackupService.swift
//  功能：备份与恢复 —— 整库备份、按选择备份（exportIds）、导入时合并或覆盖。
//  要点：部分备份（inkreader-select-*）导入时强制降级为合并，否则会把没备份的书删掉。

import Foundation
import ZIPFoundation

// MARK: - 备份包说明

struct BackupManifest: Codable {
    var version: Int = 1
    var createdAt: Date = Date()
    var app: String = "InkReader"
    var bookCount: Int = 0
    var includesContent: Bool = true
    /// 只备份了哪几本书（nil = 全库）
    var bookIds: [UUID]?
}

struct BackupSummary {
    var books: Int = 0
    var bytes: Int64 = 0
    var annotations: Int = 0
}

enum BackupMode: String, CaseIterable, Identifiable {
    case merge
    case overwrite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: return "合并"
        case .overwrite: return "覆盖"
        }
    }

    var detail: String {
        switch self {
        case .merge: return "保留现在的书，只把备份里没有的补进来；同一本书以现有进度为准。"
        case .overwrite: return "先清空现在的书架和笔记，再用备份整体替换。"
        }
    }
}

enum BackupError: LocalizedError {
    case cannotCreateArchive
    case notABackup
    case emptyBackup

    var errorDescription: String? {
        switch self {
        case .cannotCreateArchive: return "创建备份文件失败"
        case .notABackup: return "这个文件不是墨阅的备份包"
        case .emptyBackup: return "备份包里没有书"
        }
    }
}

// MARK: - 备份 / 恢复

/// 整库打包成 zip。可以只打包选中的几本书（多选备份），也可以全库。
///
/// 包内结构（相对路径）：
/// ```
/// manifest.json
/// library.json  readingsettings.json  annotations.json  collections.json
/// Books/<原文件名>
/// Covers/<封面文件名>
/// Drawings/<bookId>/<anchor>.drawing
/// ```
enum BackupService {
    static let fileExtension = "inkreader"

    // MARK: 导出

    /// - Parameter only: 只备份这些书；传 nil 表示全库
    /// - Returns: 备份文件 URL 与统计
    static func exportBackup(
        only: Set<UUID>?,
        library: LibraryStore,
        collections: CollectionStore,
        annotations: AnnotationStore,
        toZip zipURL: URL
    ) throws -> BackupSummary {
        let fm = FileManager.default
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("inkreader-backup-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }

        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        if fm.fileExists(atPath: zipURL.path) { try fm.removeItem(at: zipURL) }

        let books = library.books.filter { only == nil || only!.contains($0.id) }
        let bookIds = Set(books.map { $0.id })

        // 1) 元数据
        // 清单记实际导出的书：only 为 nil 表示全量，这时记 nil 反而丢信息。
        // 排序是为了同一个书架导两次能拿到一样的 manifest。
        let exportedIds = books.map { $0.id }.sorted { $0.uuidString < $1.uuidString }
        let manifest = BackupManifest(bookCount: books.count, bookIds: exportedIds)
        try write(manifest, to: staging.appendingPathComponent("manifest.json"))
        try write(books, to: staging.appendingPathComponent("library.json"))
        try write(library.settings, to: staging.appendingPathComponent("readingsettings.json"))
        try write(collections.collections, to: staging.appendingPathComponent("collections.json"))

        let anns = AnnotationSnapshot(
            bookmarks: annotations.bookmarks.filter { bookIds.contains($0.bookId) },
            notes: annotations.notes.filter { bookIds.contains($0.bookId) },
            highlights: annotations.highlights.filter { bookIds.contains($0.bookId) }
        )
        try write(anns, to: staging.appendingPathComponent("annotations.json"))

        // 2) 原始文件 + 封面 + 涂鸦
        let booksDir = staging.appendingPathComponent("Books", isDirectory: true)
        let coversDir = staging.appendingPathComponent("Covers", isDirectory: true)
        let drawsDir = staging.appendingPathComponent("Drawings", isDirectory: true)
        try fm.createDirectory(at: booksDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: coversDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: drawsDir, withIntermediateDirectories: true)

        var bytes: Int64 = 0
        for book in books {
            if fm.fileExists(atPath: book.fileURL.path) {
                try? fm.copyItem(at: book.fileURL, to: booksDir.appendingPathComponent(book.fileName))
                bytes += Storage.fileSize(at: book.fileURL)
            }
            if let cover = book.coverURL, fm.fileExists(atPath: cover.path) {
                try? fm.copyItem(at: cover, to: coversDir.appendingPathComponent(cover.lastPathComponent))
                bytes += Storage.fileSize(at: cover)
            }
            let anchors = annotations.drawingAnchors(for: book.id)
            if !anchors.isEmpty {
                let target = drawsDir.appendingPathComponent(book.id.uuidString, isDirectory: true)
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                for anchor in anchors {
                    let src = Storage.drawingsDirectory(for: book.id)
                        .appendingPathComponent("\(anchor).drawing")
                    try? fm.copyItem(at: src, to: target.appendingPathComponent("\(anchor).drawing"))
                    bytes += Storage.fileSize(at: src)
                }
            }
        }

        try fm.zipItem(at: staging, to: zipURL, shouldKeepParent: false, compressionMethod: .deflate)

        return BackupSummary(
            books: books.count,
            bytes: (try? fm.attributesOfItem(atPath: zipURL.path)[.size] as? NSNumber)?.int64Value ?? bytes,
            annotations: anns.bookmarks.count + anns.notes.count + anns.highlights.count
        )
    }

    // MARK: 导入

    static func restoreBackup(
        fromZip zipURL: URL,
        mode: BackupMode,
        library: LibraryStore,
        collections: CollectionStore,
        annotations: AnnotationStore
    ) throws -> BackupSummary {
        let fm = FileManager.default
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("inkreader-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try fm.unzipItem(at: zipURL, to: staging)

        let libraryFile = staging.appendingPathComponent("library.json")
        guard fm.fileExists(atPath: libraryFile.path) else { throw BackupError.notABackup }

        let incoming = (try? JSONDecoder().decode([Book].self, from: Data(contentsOf: libraryFile))) ?? []
        guard !incoming.isEmpty else { throw BackupError.emptyBackup }
        let incomingIds = Set(incoming.map { $0.id })

        if mode == .overwrite {
            for book in library.books {
                try? fm.removeItem(at: book.fileURL)
                if let cover = book.coverURL { try? fm.removeItem(at: cover) }
                try? fm.removeItem(at: Storage.comicCacheDirectory.appendingPathComponent(book.id.uuidString))
                try? fm.removeItem(at: Storage.drawingsDirectory(for: book.id))
            }
            library.books.removeAll()
            annotations.bookmarks.removeAll()
            annotations.notes.removeAll()
            annotations.highlights.removeAll()
            collections.collections.removeAll()
        }

        // 1) 原始文件（合并模式下不覆盖同名已存在的文件）
        let booksDir = staging.appendingPathComponent("Books", isDirectory: true)
        let coversDir = staging.appendingPathComponent("Covers", isDirectory: true)
        Storage.ensureDirectories()
        if fm.fileExists(atPath: booksDir.path) {
            let files = (try? fm.contentsOfDirectory(atPath: booksDir.path)) ?? []
            for name in files {
                let src = booksDir.appendingPathComponent(name)
                let dst = Storage.booksDirectory.appendingPathComponent(name)
                if mode == .overwrite { try? fm.removeItem(at: dst) }
                if !fm.fileExists(atPath: dst.path) { try? fm.copyItem(at: src, to: dst) }
            }
        }
        if fm.fileExists(atPath: coversDir.path) {
            let files = (try? fm.contentsOfDirectory(atPath: coversDir.path)) ?? []
            for name in files {
                let src = coversDir.appendingPathComponent(name)
                let dst = Storage.coversDirectory.appendingPathComponent(name)
                if mode == .overwrite { try? fm.removeItem(at: dst) }
                if !fm.fileExists(atPath: dst.path) { try? fm.copyItem(at: src, to: dst) }
            }
        }

        // 2) 涂鸦
        let drawsDir = staging.appendingPathComponent("Drawings", isDirectory: true)
        if fm.fileExists(atPath: drawsDir.path) {
            let folders = (try? fm.contentsOfDirectory(atPath: drawsDir.path)) ?? []
            for folder in folders {
                let srcDir = drawsDir.appendingPathComponent(folder, isDirectory: true)
                let dstDir = Storage.drawingsDirectory.appendingPathComponent(folder, isDirectory: true)
                try? fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
                let files = (try? fm.contentsOfDirectory(atPath: srcDir.path)) ?? []
                for name in files where name.hasSuffix(".drawing") {
                    let src = srcDir.appendingPathComponent(name)
                    let dst = dstDir.appendingPathComponent(name)
                    if mode == .overwrite { try? fm.removeItem(at: dst) }
                    if !fm.fileExists(atPath: dst.path) { try? fm.copyItem(at: src, to: dst) }
                }
            }
        }

        // 3) 书架条目：合并模式下同 id 跳过（保留现有进度）
        var added = 0
        for book in incoming {
            if mode == .merge, library.books.contains(where: { $0.id == book.id }) { continue }
            if let idx = library.books.firstIndex(where: { $0.id == book.id }) {
                library.books[idx] = book
            } else {
                library.books.append(book)
            }
            added += 1
        }
        library.save()

        // 4) 收藏夹（老备份可能没有这个文件）
        if let data = try? Data(contentsOf: staging.appendingPathComponent("collections.json")),
           let incomingCollections = try? JSONDecoder().decode([BookCollection].self, from: data) {
            for item in incomingCollections {
                if let idx = collections.collections.firstIndex(where: { $0.id == item.id }) {
                    if mode == .overwrite { collections.collections[idx] = item }
                } else {
                    collections.collections.append(item)
                }
            }
            collections.save()
        }

        // 5) 笔记 / 书签 / 高亮
        if let data = try? Data(contentsOf: staging.appendingPathComponent("annotations.json")),
           let snapshot = try? JSONDecoder().decode(AnnotationSnapshot.self, from: data) {
            annotations.bookmarks = merge(annotations.bookmarks, snapshot.bookmarks, overwrite: mode == .overwrite)
            annotations.notes = merge(annotations.notes, snapshot.notes, overwrite: mode == .overwrite)
            annotations.highlights = merge(annotations.highlights, snapshot.highlights, overwrite: mode == .overwrite)
            annotations.save()
        }

        // 6) 阅读设置（只在覆盖模式套用，免得恢复一本书把全局设置改掉）
        if mode == .overwrite,
           let data = try? Data(contentsOf: staging.appendingPathComponent("readingsettings.json")),
           let settings = try? JSONDecoder().decode(ReadingSettings.self, from: data) {
            library.settings = settings
        }

        library.load()
        collections.load()
        annotations.load()

        return BackupSummary(
            books: added,
            bytes: 0,
            annotations: annotations.bookmarks.filter { incomingIds.contains($0.bookId) }.count
                + annotations.notes.filter { incomingIds.contains($0.bookId) }.count
                + annotations.highlights.filter { incomingIds.contains($0.bookId) }.count
        )
    }

    // MARK: - 小工具

    private struct AnnotationSnapshot: Codable {
        var bookmarks: [Bookmark]
        var notes: [Note]
        var highlights: [HighlightRange]
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    /// 合并两条同 id 的记录：overwrite 用新的，否则保留现有的
    private static func merge<T: Identifiable>(_ current: [T], _ incoming: [T], overwrite: Bool) -> [T] where T: Equatable {
        var result = current
        for item in incoming {
            if let idx = result.firstIndex(where: { $0.id == item.id }) {
                if overwrite { result[idx] = item }
            } else {
                result.append(item)
            }
        }
        return result
    }
}
