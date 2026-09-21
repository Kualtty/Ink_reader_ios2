//  墨阅 InkReader · InkReader/Models/Bookmark.swift
//  功能：标注模型 —— Bookmark（书签）、Note（笔记，带 kind）、HighlightRange（高亮区间）。
//  要点：偏移量一律相对全文；原文被修订后由 RevisionStore 统一平移，不要在这里自己算。

import Foundation

// MARK: - 书签

struct Bookmark: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var bookId: UUID
    /// 页码（0 开始）
    var page: Int
    /// 精确定位串：TXT/EPUB 为字符偏移，PDF/漫画为页码
    var locator: String
    /// 摘录文字
    var excerpt: String = ""
    var createdAt: Date = Date()

    init(bookId: UUID, page: Int, locator: String, excerpt: String = "") {
        self.id = UUID()
        self.bookId = bookId
        self.page = page
        self.locator = locator
        self.excerpt = excerpt
        self.createdAt = Date()
    }
}

// MARK: - 笔记（批注）

enum NoteKind: String, Codable {
    /// 手动随笔
    case memo
    /// 划词批注
    case highlight
    /// 手写涂鸦附言
    case sketch
}

struct Note: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var bookId: UUID
    var kind: NoteKind = .memo
    var page: Int
    var locator: String
    /// 被划选/摘录的原文
    var quote: String = ""
    /// 笔记正文
    var content: String = ""
    /// 高亮颜色（#RRGGBB）
    var colorHex: String = "#FFD54F"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(bookId: UUID,
         kind: NoteKind = .memo,
         page: Int,
         locator: String,
         quote: String = "",
         content: String = "",
         colorHex: String = "#FFD54F") {
        self.id = UUID()
        self.bookId = bookId
        self.kind = kind
        self.page = page
        self.locator = locator
        self.quote = quote
        self.content = content
        self.colorHex = colorHex
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - 划词高亮范围（仅 TXT/EPUB 使用）

struct HighlightRange: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var bookId: UUID
    /// 全文字符起始
    var start: Int
    var length: Int
    var colorHex: String = "#FFD54F"
    var noteId: UUID?

    init(bookId: UUID, start: Int, length: Int, colorHex: String = "#FFD54F", noteId: UUID? = nil) {
        self.id = UUID()
        self.bookId = bookId
        self.start = start
        self.length = length
        self.colorHex = colorHex
        self.noteId = noteId
    }

    var range: NSRange { NSRange(location: start, length: length) }
}
