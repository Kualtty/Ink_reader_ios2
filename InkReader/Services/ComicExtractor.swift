//  墨阅 InkReader · InkReader/Services/ComicExtractor.swift
//  功能：漫画 / 压缩包解压 —— 把 cbz、zip、散图解压成有序的页文件并返回路径。
//  要点：解压落在 Caches，可能被系统清理，所以页序不能存绝对路径。

import Foundation
import ZIPFoundation

/// 漫画包（CBZ / ZIP）解压 与 图片排序
enum ComicExtractor {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "heic", "tiff"]

    static func isImage(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// 解包并返回按顺序排列的图片地址（带缓存）
    static func extractImages(for book: Book) throws -> [URL] {
        let dest = Storage.comicCacheDirectory.appendingPathComponent(book.id.uuidString, isDirectory: true)
        let cached = sortedImages(in: dest)
        if !cached.isEmpty { return cached }

        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        let source = book.fileURL
        guard let archive = Archive(url: source, accessMode: .read) else {
            throw ImportError.readFailed
        }

        for entry in archive where entry.type == .file {
            guard isImage(entry.path) else { continue }
            let target = dest.appendingPathComponent(entry.path)
            try? FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            _ = try? archive.extract(entry, to: target)
        }

        let images = sortedImages(in: dest)
        guard !images.isEmpty else { throw ImportError.noImages }
        return images
    }

    /// 递归收集并自然排序
    static func sortedImages(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            if isImage(url.path) { urls.append(url) }
        }
        urls.sort { naturalCompare($0.path, $1.path) }
        return urls
    }

    /// 自然排序（1, 2, 10 而不是 1, 10, 2）
    static func naturalCompare(_ a: String, _ b: String) -> Bool {
        let ai = a.indices
        let bi = b.indices
        var i = ai.startIndex
        var j = bi.startIndex

        while i < ai.endIndex, j < bi.endIndex {
            if a[i].isNumber, b[j].isNumber {
                // 比较连续数字段
                var iEnd = i
                var jEnd = j
                while iEnd < ai.endIndex, a[iEnd].isNumber { iEnd = a.index(after: iEnd) }
                while jEnd < bi.endIndex, b[jEnd].isNumber { jEnd = b.index(after: jEnd) }
                let na = Int(a[i..<iEnd]) ?? 0
                let nb = Int(b[j..<jEnd]) ?? 0
                if na != nb { return na < nb }
                i = iEnd
                j = jEnd
            } else if a[i] == b[j] {
                i = a.index(after: i)
                j = b.index(after: j)
            } else {
                return String(a[i]).localizedStandardCompare(String(b[j])) == .orderedAscending
            }
        }
        return a.count < b.count
    }
}
