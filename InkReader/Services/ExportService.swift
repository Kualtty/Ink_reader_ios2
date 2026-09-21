//  墨阅 InkReader · InkReader/Services/ExportService.swift
//  功能：导出 —— 笔记导出为 Markdown、导出原文件、iPad 分享面板（ActivityView）。
//  要点：iPad 上必须给 popover 设 sourceView 且清空箭头方向，否则直接崩溃。

import Foundation
import SwiftUI
import UIKit

/// 系统分享面板
///
/// iPad 上 UIActivityViewController 没有 popover 锚点会直接崩，
/// 这里把锚点挂在自己身上，并把小箭头关掉，表现就跟一张普通 sheet 一样。
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    var onDone: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onDone?() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        guard let popover = controller.popoverPresentationController,
              popover.sourceView == nil else { return }
        popover.sourceView = controller.view
        popover.sourceRect = CGRect(
            x: controller.view.bounds.midX,
            y: controller.view.bounds.midY,
            width: 0,
            height: 0
        )
        popover.permittedArrowDirections = []
    }
}

// MARK: - 导出

enum ExportService {
    /// 原文件导出到临时目录，换成「书名.扩展名」这种能看懂的名字
    static func exportableFileURL(for book: Book) -> URL? {
        guard FileManager.default.fileExists(atPath: book.fileURL.path) else { return nil }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("InkReaderExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = sanitized(book.title)
        let ext = book.fileURL.pathExtension.lowercased()
        let target = directory.appendingPathComponent("\(base).\(ext)")
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.copyItem(at: book.fileURL, to: target)
        } catch {
            return nil
        }
        return target
    }

    /// 笔记 / 书签 / 高亮 导出成 Markdown
    static func notesMarkdown(book: Book,
                             annotations: AnnotationStore,
                             fullText: String = "") -> String {
        let notes = annotations.notes(for: book.id)
        let bookmarks = annotations.bookmarks(for: book.id)
        let highlights = annotations.highlights(for: book.id)

        var lines: [String] = []
        lines.append("# \(book.title)")
        var meta: [String] = []
        if !book.author.isEmpty { meta.append(book.author) }
        meta.append(book.format.displayName)
        meta.append("进度 \(Int(book.progress * 100))%")
        lines.append("> " + meta.joined(separator: " · "))
        lines.append("")

        lines.append("## 笔记（\(notes.count)）")
        lines.append("")
        if notes.isEmpty {
            lines.append("_还没有笔记_")
        } else {
            for note in notes {
                lines.append("- **第 \(note.page + 1) 页**")
                if !note.quote.trimmed.isEmpty {
                    lines.append("  - 原文：\(note.quote.trimmed)")
                }
                if !note.content.trimmed.isEmpty {
                    lines.append("  - 批注：\(note.content.trimmed)")
                }
            }
        }
        lines.append("")

        lines.append("## 书签（\(bookmarks.count)）")
        lines.append("")
        if bookmarks.isEmpty {
            lines.append("_还没有书签_")
        } else {
            for mark in bookmarks {
                let excerpt = mark.excerpt.trimmed
                lines.append("- 第 \(mark.page + 1) 页"
                             + (excerpt.isEmpty ? "" : " · \(excerpt)"))
            }
        }
        lines.append("")

        lines.append("## 高亮（\(highlights.count)）")
        lines.append("")
        if highlights.isEmpty {
            lines.append("_还没有高亮_")
        } else {
            let ns = fullText as NSString
            for item in highlights {
                var quote = ""
                if ns.length > 0 {
                    let loc = min(max(0, item.start), ns.length - 1)
                    let len = min(item.length, ns.length - loc)
                    quote = ns.substring(with: NSRange(location: loc, length: len))
                }
                lines.append("- " + (quote.trimmed.isEmpty ? "偏移 \(item.start)" : quote.trimmed))
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func notesMarkdownFile(book: Book,
                                  annotations: AnnotationStore,
                                  fullText: String = "") -> URL? {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("InkReaderExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("\(sanitized(book.title))-笔记.md")
        let text = notesMarkdown(book: book, annotations: annotations, fullText: fullText)
        do {
            try text.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        return target
    }

    /// 文件名里不能带 / : 之类，iPad 上会让分享失败
    private static func sanitized(_ raw: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let base = raw.unicodeScalars
            .map { banned.contains($0) ? "_" : Character($0) }
        let text = String(base).trimmed
        return text.isEmpty ? "未命名" : String(text.prefix(60))
    }
}
