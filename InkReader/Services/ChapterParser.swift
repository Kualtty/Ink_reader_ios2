//  墨阅 InkReader · InkReader/Services/ChapterParser.swift
//  功能：目录解析 —— 用正则从 TXT 正文里抽出章节标题与字符位置。
//  要点：命中规则见文件内正则；解析结果供 ChapterListView 跳转使用。

import Foundation

/// 章节目录识别（TXT / EPUB 转文本后通用）
enum ChapterParser {
    private static let patterns: [[String]] = [
        [#"^\s*(?:序章|序言|前言|引子|楔子|后记|尾声|番外|附录)[^\n]{0,40}$"#],
        [#"^\s*(?:卷|篇|部)?\s*第\s*[0-9零一二三四五六七八九十百千两〇○]{1,10}\s*(?:章|节|回|卷|篇|部|集|幕)[^\n]{0,60}$"#],
        [#"^\s*(?:Chapter|CHAPTER|chapter)\s+[0-9IVXLCivxlc]+[^\n]{0,60}$"#],
        [#"^\s*[0-9]{1,4}\s*[\.、．]\s*[^\n]{1,40}$"#]
    ]

    /// 最大目录条目数量，避免把正文编号行也吞进来
    private static let maxChapters = 3000

    static func parse(text: String) -> [Chapter] {
        var results: [Chapter] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        for (level, group) in patterns.enumerated() {
            for pattern in group {
                guard let regex = try? NSRegularExpression(
                    pattern: pattern,
                    options: [.anchorsMatchLines, .caseInsensitive]
                ) else { continue }
                let matches = regex.matches(in: text, options: [], range: fullRange)
                for match in matches {
                    let title = nsText.substring(with: match.range).trimmed
                    guard !title.isEmpty, title.count <= 80 else { continue }
                    results.append(Chapter(title: title, offset: match.range.location, level: level))
                }
            }
        }

        results.sort { $0.offset < $1.offset }

        // 去重：同一行附近的保留第一个；去掉与上一条距离过近的
        var deduped: [Chapter] = []
        for chapter in results {
            if let last = deduped.last, chapter.offset - last.offset < 2 { continue }
            if let last = deduped.last, last.title == chapter.title, chapter.offset - last.offset < 200 { continue }
            deduped.append(chapter)
            if deduped.count >= maxChapters { break }
        }

        // 若完全没识别到章节，生成"全文"单章
        if deduped.isEmpty {
            deduped.append(Chapter(title: "全文", offset: 0, level: 0))
        } else if deduped.first?.offset ?? 0 > 0 {
            deduped.insert(Chapter(title: "开头", offset: 0, level: 0), at: 0)
        }
        return deduped
    }

    /// 找出当前字符偏移所属的章节索引
    static func index(of offset: Int, in chapters: [Chapter]) -> Int {
        var low = 0, high = chapters.count - 1, result = 0
        while low <= high {
            let mid = (low + high) / 2
            if chapters[mid].offset <= offset {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    /// 正文清洗后用于分页展示：为章节标题加粗
    static func attributedText(from text: String, chapters: [Chapter], settings: ReadingSettings) -> NSAttributedString {
        let nsText = text as NSString
        let result = NSMutableAttributedString(string: text, attributes: settings.baseAttributes)
        for chapter in chapters where chapter.level < 3 {
            let start = min(chapter.offset, nsText.length)
            guard start < nsText.length else { continue }
            // 以换行作为章节标题行的结束
            let remain = NSRange(location: start, length: nsText.length - start)
            let newline = nsText.range(of: "\n", options: [], range: remain)
            let end = newline.location == NSNotFound ? nsText.length : newline.location
            let range = NSRange(location: start, length: max(0, end - start))
            guard range.length > 0 else { continue }
            result.addAttributes(settings.titleAttributes, range: range)
        }
        return result
    }
}
