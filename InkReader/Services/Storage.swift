//  墨阅 InkReader · InkReader/Services/Storage.swift
//  功能：存储路径 —— 统一给出 Documents/Books、Caches、涂鸦目录等路径并负责创建。
//  要点：新加目录在这里登记，别在各处硬拼路径。

import Foundation

enum Storage {
    static let documents: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    static let booksDirectory = documents.appendingPathComponent("Books", isDirectory: true)
    static let coversDirectory = documents.appendingPathComponent("Covers", isDirectory: true)
    static let annotationsDirectory = documents.appendingPathComponent("Annotations", isDirectory: true)
    static let drawingsDirectory = annotationsDirectory.appendingPathComponent("Drawings", isDirectory: true)

    static let comicCacheDirectory: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Comics", isDirectory: true)
    }()

    static let libraryFile = documents.appendingPathComponent("library.json")
    static let settingsFile = documents.appendingPathComponent("readingsettings.json")
    static let annotationsFile = documents.appendingPathComponent("annotations.json")
    static let collectionsFile = documents.appendingPathComponent("collections.json")

    static func ensureDirectories() {
        let dirs = [booksDirectory, coversDirectory, annotationsDirectory, drawingsDirectory, comicCacheDirectory]
        for dir in dirs {
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    /// 涂鸦文件：Documents/Annotations/Drawings/<bookId>/<key>.drawing
    static func drawingURL(bookId: UUID, key: String) -> URL {
        let dir = drawingsDirectory.appendingPathComponent(bookId.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(safeName(key)).drawing")
    }

    static func drawingsDirectory(for bookId: UUID) -> URL {
        let dir = drawingsDirectory.appendingPathComponent(bookId.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func safeName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scaled = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(scaled)
    }

    static func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
}
