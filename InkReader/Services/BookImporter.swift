//  墨阅 InkReader · InkReader/Services/BookImporter.swift
//  功能：导入 —— 按扩展名把文件分发到 txt / pdf / epub / cbz / 图片，写入 Books 目录、抽封面、登记书架。
//  要点：依赖 Book(id:title:format:...) 成员构造器，改 Book 的解码方式时要回来确认这里没受影响。

import Foundation
import PDFKit
import UIKit
import ZIPFoundation

enum ImportError: LocalizedError {
    case unsupported
    case readFailed
    case noImages

    var errorDescription: String? {
        switch self {
        case .unsupported: return "暂不支持该文件格式"
        case .readFailed: return "文件读取失败或已损坏"
        case .noImages: return "压缩包内没有找到图片"
        }
    }
}

struct BookImporter {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "heic"]

    // MARK: - 批量导入入口

    /// 支持：txt / md / pdf / epub / cbz / zip / 多张图片
    @discardableResult
    static func importBooks(from urls: [URL]) -> [Book] {
        for url in urls { _ = url.startAccessingSecurityScopedResource() }
        defer { for url in urls { url.stopAccessingSecurityScopedResource() } }

        var books: [Book] = []

        let images = urls.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { ComicExtractor.naturalCompare($0.lastPathComponent, $1.lastPathComponent) }
        let documents = urls.filter { !imageExtensions.contains($0.pathExtension.lowercased()) }

        if !images.isEmpty, let book = try? importImageSet(images) {
            books.append(book)
        }
        for url in documents {
            if let book = try? importSingle(url) {
                books.append(book)
            }
        }
        return books
    }

    // MARK: - 单个文件

    static func importSingle(_ url: URL) throws -> Book {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "txt", "text", "md":
            return try importText(url)
        case "pdf":
            return try importPDF(url)
        case "epub":
            return try importEPUB(url)
        case "cbz", "zip":
            return try importComic(url)
        default:
            throw ImportError.unsupported
        }
    }

    // MARK: TXT

    private static func importText(_ url: URL) throws -> Book {
        let data = try Data(contentsOf: url)
        guard let text = TextEncodingDetector.decode(data), !text.trimmed.isEmpty else {
            throw ImportError.readFailed
        }
        let fileName = "\(UUID().uuidString).txt"
        let target = Storage.booksDirectory.appendingPathComponent(fileName)
        try text.write(to: target, atomically: true, encoding: .utf8)

        let id = UUID()
        let title = guessTitle(from: text, fallback: url.deletingPathExtension().lastPathComponent)
        let cover = saveCover(makeTextCover(title: title, author: ""), id: id)

        return Book(
            id: id,
            title: title,
            format: .txt,
            fileName: fileName,
            coverFileName: cover,
            fileSize: Storage.fileSize(at: target)
        )
    }

    // MARK: EPUB

    private static func importEPUB(_ url: URL) throws -> Book {
        let parsed = try EPUBParser.parse(url: url)
        let fileName = "\(UUID().uuidString).txt"
        let target = Storage.booksDirectory.appendingPathComponent(fileName)
        try parsed.text.write(to: target, atomically: true, encoding: .utf8)

        let id = UUID()
        let title = parsed.title.isEmpty
            ? url.deletingPathExtension().lastPathComponent
            : parsed.title
        let cover = saveCover(makeTextCover(title: title, author: parsed.author), id: id)

        return Book(
            id: id,
            title: title,
            author: parsed.author,
            format: .epub,
            fileName: fileName,
            coverFileName: cover,
            fileSize: Storage.fileSize(at: target)
        )
    }

    // MARK: PDF

    private static func importPDF(_ url: URL) throws -> Book {
        guard let document = PDFDocument(url: url) else { throw ImportError.readFailed }
        let fileName = "\(UUID().uuidString).pdf"
        let target = Storage.booksDirectory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: url, to: target)

        let id = UUID()
        let metaTitle = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?.trimmed
        let title = (metaTitle?.isEmpty == false) ? metaTitle! : url.deletingPathExtension().lastPathComponent
        let author = (document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String) ?? ""

        var cover: String?
        if let page = document.page(at: 0) {
            let thumb = page.thumbnail(of: CGSize(width: 300, height: 420), for: .cropBox)
            cover = saveCover(thumb, id: id)
        }

        var book = Book(
            id: id,
            title: title,
            author: author,
            format: .pdf,
            fileName: fileName,
            coverFileName: cover,
            fileSize: Storage.fileSize(at: target)
        )
        book.totalPages = document.pageCount
        return book
    }

    // MARK: 漫画包

    private static func importComic(_ url: URL) throws -> Book {
        let fileName = "\(UUID().uuidString).cbz"
        let target = Storage.booksDirectory.appendingPathComponent(fileName)
        if url.pathExtension.lowercased() == "zip" {
            try FileManager.default.copyItem(at: url, to: target)
        } else {
            try FileManager.default.copyItem(at: url, to: target)
        }

        let id = UUID()
        var book = Book(
            id: id,
            title: url.deletingPathExtension().lastPathComponent,
            format: .comic,
            fileName: fileName,
            fileSize: Storage.fileSize(at: target)
        )

        let images = try ComicExtractor.extractImages(for: book)
        book.totalPages = images.count
        if let first = images.first {
            book.coverFileName = saveCover(downscale(imageAt: first, maxWidth: 300), id: id)
        }
        return book
    }

    // MARK: 多张图片 -> 打包成 CBZ

    private static func importImageSet(_ urls: [URL]) throws -> Book {
        let fileName = "\(UUID().uuidString).cbz"
        let target = Storage.booksDirectory.appendingPathComponent(fileName)
        guard let archive = Archive(url: target, accessMode: .create) else { throw ImportError.readFailed }

        for (index, url) in urls.enumerated() {
            let name = String(format: "%06d.%@", index, url.pathExtension.lowercased())
            try? archive.addEntry(with: name, fileURL: url)
        }

        let id = UUID()
        var book = Book(
            id: id,
            title: "图片集 " + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short),
            format: .comic,
            fileName: fileName,
            fileSize: Storage.fileSize(at: target)
        )
        let images = try ComicExtractor.extractImages(for: book)
        book.totalPages = images.count
        if let first = images.first {
            book.coverFileName = saveCover(downscale(imageAt: first, maxWidth: 300), id: id)
        }
        return book
    }

    // MARK: - 从「文件」App 投放到 Documents 的书

    static func importInboxFiles() -> [Book] {
        var found: [URL] = []
        let roots = [
            Storage.documents,
            Storage.documents.appendingPathComponent("Inbox", isDirectory: true)
        ]
        let allowed = Set(BookFormat.importableExtensions)
        for root in roots {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            found.append(contentsOf: items.filter { allowed.contains($0.pathExtension.lowercased()) })
        }
        guard !found.isEmpty else { return [] }

        let books = importBooks(from: found)
        for url in found { try? FileManager.default.removeItem(at: url) }
        return books
    }

    // MARK: - 辅助

    private static func guessTitle(from text: String, fallback: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.prefix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 2, trimmed.count <= 40, !trimmed.contains("。") {
                return trimmed
            }
        }
        return fallback
    }

    private static func saveCover(_ image: UIImage?, id: UUID) -> String? {
        guard let image = image, let data = image.pngData() else { return nil }
        let name = "\(id.uuidString).png"
        let url = Storage.coversDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        return name
    }

    private static func imageAt(_ url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private static func downscale(imageAt url: URL, maxWidth: CGFloat) -> UIImage? {
        guard let image = imageAt(url) else { return nil }
        let ratio = min(1, maxWidth / image.size.width)
        guard ratio < 1 else { return image }
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func makeTextCover(title: String, author: String) -> UIImage? {
        let size = CGSize(width: 300, height: 420)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor(hex: "#5A6C8A").cgColor, UIColor(hex: "#2F3B4C").cgColor]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: nil
            ) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            } else {
                UIColor.darkGray.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }

            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor.white,
                .paragraphStyle: style
            ]
            let authorAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15),
                .foregroundColor: UIColor(white: 1, alpha: 0.75),
                .paragraphStyle: style
            ]

            let titleRect = CGRect(x: 26, y: 70, width: size.width - 52, height: size.height - 200)
            (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)

            if !author.isEmpty {
                let rect = CGRect(x: 26, y: size.height - 110, width: size.width - 52, height: 40)
                (author as NSString).draw(in: rect, withAttributes: authorAttrs)
            }
        }
    }
}
