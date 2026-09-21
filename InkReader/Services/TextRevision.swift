//  墨阅 InkReader · InkReader/Services/TextRevision.swift
//  功能：原文修订 —— 记录每次正文改动，平移受影响的标注，标记失效标注，支持撤销与重新定位。
//  要点：平移规则 —— 整体在前不动 / 整体在后 ±delta / 包住改动只改长度 / 部分重叠标失效。仅 TXT 与 EPUB 可用。

import Foundation

// MARK: - 修订记录

/// 一次「编辑原文」的完整记录
///
/// 存下来有两个用处：
/// 1) 撤销 —— 拿它算出反向修订，把原文换回去；
/// 2) 平移标注 —— 改原文会让后面所有标注的字符偏移整体位移，靠 delta 修正。
struct TextRevision: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var bookId: UUID
    var createdAt: Date = Date()
    /// 改动起点（改动**前**全文里的字符偏移，UTF-16）
    var location: Int
    /// 被替换掉的原文长度（UTF-16）
    var oldLength: Int
    var oldText: String
    var newText: String

    init(bookId: UUID,
         location: Int,
         oldLength: Int,
         oldText: String,
         newText: String) {
        self.id = UUID()
        self.bookId = bookId
        self.createdAt = Date()
        self.location = location
        self.oldLength = oldLength
        self.oldText = oldText
        self.newText = newText
    }

    /// 长度变化量（UTF-16），负数表示改短了
    var delta: Int { (newText as NSString).length - oldLength }

    /// 反向记录：把新文本换回旧文本
    var inverse: TextRevision {
        TextRevision(
            bookId: bookId,
            location: location,
            oldLength: (newText as NSString).length,
            oldText: newText,
            newText: oldText
        )
    }
}

// MARK: - 失效标注

/// 改原文时没跟上的标注
///
/// 内容一条都不丢：quote 里留着当时的原文，界面上标「⚠ 失效」，
/// 用户点「重新定位」就在新原文里再搜一次这段字，搜到就恢复到原位。
struct OrphanAnnotation: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case highlight
        case bookmark
        case note
    }

    /// 沿用原标注的 id，恢复时用它去重
    var id: UUID
    var bookId: UUID
    var kind: Kind
    /// 重新定位用的原文片段
    var quote: String
    /// 失效前最后一次已知的偏移
    var lastOffset: Int
    /// 笔记正文 / 书签摘录
    var detail: String = ""
    var colorHex: String = "#FFD54F"
    var createdAt: Date = Date()

    var kindTitle: String {
        switch kind {
        case .highlight: return "高亮"
        case .bookmark: return "书签"
        case .note: return "笔记"
        }
    }
}

// MARK: - 修订引擎

/// 只负责「改字符串 + 重算章节」，不碰任何 Store，方便单独推演
enum TextRevisionEngine {
    struct Outcome {
        var text: String
        var chapters: [Chapter]
        /// 实际生效的长度变化（会被边界夹过，不一定等于 revision.delta）
        var delta: Int
        /// 实际生效的替换范围
        var range: NSRange
    }

    static func apply(_ revision: TextRevision, to text: String) -> Outcome {
        let ns = text as NSString
        // 存档里记的偏移可能已经越界（比如之前在别处改过），这里先夹回合法区间
        let loc = min(max(0, revision.location), ns.length)
        let len = min(max(0, revision.oldLength), ns.length - loc)
        let range = NSRange(location: loc, length: len)
        let next = ns.replacingCharacters(in: range, with: revision.newText)
        return Outcome(
            text: next,
            chapters: ChapterParser.parse(text: next),
            delta: (revision.newText as NSString).length - len,
            range: range
        )
    }
}

// MARK: - 修订仓库

/// 修订记录 + 失效标注的持久化，以及「改原文 → 平移标注」这套联动
final class RevisionStore: ObservableObject {
    @Published private(set) var revisions: [TextRevision] = []
    @Published private(set) var orphans: [OrphanAnnotation] = []

    private struct Persisted: Codable {
        var revisions: [TextRevision]
        var orphans: [OrphanAnnotation]
    }

    private static var file: URL {
        Storage.documents.appendingPathComponent("revisions.json")
    }

    init() {
        load()
    }

    // MARK: 持久化

    func load() {
        guard let data = try? Data(contentsOf: Self.file),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        revisions = decoded.revisions
        orphans = decoded.orphans
    }

    func save() {
        let payload = Persisted(revisions: revisions, orphans: orphans)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: Self.file, options: .atomic)
    }

    // MARK: 查询

    func revisions(for bookId: UUID) -> [TextRevision] {
        revisions.filter { $0.bookId == bookId }.sorted { $0.createdAt < $1.createdAt }
    }

    func orphans(for bookId: UUID) -> [OrphanAnnotation] {
        orphans.filter { $0.bookId == bookId }.sorted { $0.createdAt < $1.createdAt }
    }

    var totalOrphanCount: Int { orphans.count }

    // MARK: 应用 / 撤销

    /// 落地一次修订：改字符串、平移标注、记一笔，返回新的全文
    @discardableResult
    func apply(_ revision: TextRevision,
               to text: String,
               annotations: AnnotationStore) -> String {
        perform(revision, to: text, annotations: annotations, record: true)
    }

    /// 撤销某本书最后一次修订；没有可撤的就返回 nil
    func undoLast(bookId: UUID,
                  text: String,
                  annotations: AnnotationStore) -> String? {
        guard let last = revisions(for: bookId).last,
              let index = revisions.firstIndex(where: { $0.id == last.id }) else { return nil }
        revisions.remove(at: index)
        let result = perform(last.inverse, to: text, annotations: annotations, record: false)
        save()
        return result
    }

    /// 把失效标注放回原位：在新原文里搜它记的那段字
    @discardableResult
    func relocate(_ orphan: OrphanAnnotation,
                  in text: String,
                  annotations: AnnotationStore) -> Bool {
        let ns = text as NSString
        let found = ns.range(of: orphan.quote)
        guard found.location != NSNotFound, found.length > 0 else { return false }

        switch orphan.kind {
        case .highlight:
            if !annotations.highlights.contains(where: { $0.id == orphan.id }) {
                var item = HighlightRange(
                    bookId: orphan.bookId,
                    start: found.location,
                    length: found.length,
                    colorHex: orphan.colorHex
                )
                item.id = orphan.id
                annotations.addHighlight(item)
            }
        case .bookmark:
            if !annotations.bookmarks.contains(where: { $0.id == orphan.id }) {
                var item = Bookmark(
                    bookId: orphan.bookId,
                    page: 0,
                    locator: String(found.location),
                    excerpt: orphan.quote
                )
                item.id = orphan.id
                annotations.bookmarks.append(item)
            }
        case .note:
            if !annotations.notes.contains(where: { $0.id == orphan.id }) {
                var item = Note(
                    bookId: orphan.bookId,
                    kind: .highlight,
                    page: 0,
                    locator: String(found.location),
                    quote: orphan.quote,
                    content: orphan.detail,
                    colorHex: orphan.colorHex
                )
                item.id = orphan.id
                annotations.notes.append(item)
            }
        }

        orphans.removeAll { $0.id == orphan.id && $0.bookId == orphan.bookId }
        annotations.save()
        save()
        return true
    }

    func dropOrphan(_ orphan: OrphanAnnotation) {
        orphans.removeAll { $0.id == orphan.id && $0.bookId == orphan.bookId }
        save()
    }

    /// 删书时把它的修订记录一起清掉
    func clear(bookId: UUID) {
        revisions.removeAll { $0.bookId == bookId }
        orphans.removeAll { $0.bookId == bookId }
        save()
    }

    /// 清库：全部抹掉
    func reset() {
        revisions = []
        orphans = []
        save()
    }

    // MARK: 内部

    @discardableResult
    private func perform(_ revision: TextRevision,
                         to text: String,
                         annotations: AnnotationStore,
                         record: Bool) -> String {
        let outcome = TextRevisionEngine.apply(revision, to: text)
        shift(bookId: revision.bookId,
              annotations: annotations,
              range: outcome.range,
              delta: outcome.delta,
              oldText: text)
        if record {
            revisions.append(revision)
        }
        // 每次改完都再试一次：说不定之前失效的标注这回能找回来
        reattachOrphans(bookId: revision.bookId, in: outcome.text, annotations: annotations)
        save()
        return outcome.text
    }

    /// 平移 / 判定失效
    ///
    /// 三类情况：
    /// - 整段在改动点之前 → 不动
    /// - 整段在改动点之后 → 整体平移 delta
    /// - 把改动点整个包在里面 → 位置不动，长度跟着变
    /// - 其余（部分重叠）→ 标失效，等用户重新定位
    private func shift(bookId: UUID,
                       annotations: AnnotationStore,
                       range: NSRange,
                       delta: Int,
                       oldText: String) {
        let loc = range.location
        let oldEnd = NSMaxRange(range)
        let ns = oldText as NSString

        // 高亮
        for idx in annotations.highlights.indices
        where annotations.highlights[idx].bookId == bookId {
            var item = annotations.highlights[idx]
            let start = item.start
            let end = start + item.length
            if end <= loc {
                continue
            } else if start >= oldEnd {
                item.start += delta
            } else if start <= loc && end >= oldEnd {
                item.length = max(0, item.length + delta)
            } else {
                let safe = NSRange(
                    location: min(max(0, start), ns.length),
                    length: min(item.length, max(0, ns.length - start))
                )
                orphans.append(
                    OrphanAnnotation(
                        id: item.id,
                        bookId: bookId,
                        kind: .highlight,
                        quote: safe.length > 0 ? ns.substring(with: safe) : "",
                        lastOffset: start,
                        colorHex: item.colorHex
                    )
                )
                item.length = -1     // 标记待删
            }
            annotations.highlights[idx] = item
        }
        annotations.highlights.removeAll { $0.length < 0 }

        // 书签与笔记：按字符点位移
        for idx in annotations.bookmarks.indices
        where annotations.bookmarks[idx].bookId == bookId {
            var item = annotations.bookmarks[idx]
            guard let offset = Int(item.locator) else { continue }
            if offset < loc {
                continue
            } else if offset >= oldEnd {
                item.locator = String(max(0, offset + delta))
            } else {
                item.locator = String(loc)     // 落在被改区间里：贴到改动起点
            }
            annotations.bookmarks[idx] = item
        }

        for idx in annotations.notes.indices
        where annotations.notes[idx].bookId == bookId {
            var item = annotations.notes[idx]
            guard let offset = Int(item.locator) else { continue }
            if offset < loc {
                continue
            } else if offset >= oldEnd {
                item.locator = String(max(0, offset + delta))
            } else {
                item.locator = String(loc)
            }
            annotations.notes[idx] = item
        }

        annotations.save()
    }

    /// 改完原文后，把还能找回去的失效标注自动接上
    private func reattachOrphans(bookId: UUID,
                                 in text: String,
                                 annotations: AnnotationStore) {
        let pending = orphans(for: bookId)
        guard !pending.isEmpty else { return }
        for orphan in pending where !orphan.quote.isEmpty {
            _ = relocate(orphan, in: text, annotations: annotations)
        }
    }
}
