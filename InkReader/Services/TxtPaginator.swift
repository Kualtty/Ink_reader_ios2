//  墨阅 InkReader · InkReader/Services/TxtPaginator.swift
//  功能：TXT 分页 —— TextKit 多 NSTextContainer 后台分页，带 NSLock 保护结果。
//  要点：页码由字号与页面尺寸决定，改设置会触发重新分页。

import UIKit

/// TXT / EPUB 纯文本分页引擎（TextKit 多容器方案）
final class TxtPaginator {
    let text: NSAttributedString
    private static let queue = DispatchQueue(label: "com.inkreader.paginator", qos: .userInitiated)
    private static let lock = NSLock()

    init(text: NSAttributedString) {
        self.text = text
    }

    /// 在后台线程分页。返回每一页对应的全局 NSRange。
    static func paginate(_ text: NSAttributedString,
                         pageSize: CGSize,
                         completion: @escaping ([NSRange]) -> Void) {
        let copy = NSAttributedString(attributedString: text)
        queue.async {
            lock.lock()
            let ranges = Self.performPagination(text: copy, pageSize: pageSize)
            lock.unlock()
            DispatchQueue.main.async { completion(ranges) }
        }
    }

    /// 同步分页（测试 / 小文本使用）
    static func performPagination(text: NSAttributedString, pageSize: CGSize) -> [NSRange] {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = false
        storage.addLayoutManager(layoutManager)
        storage.setAttributedString(text)

        let total = storage.length
        guard total > 0 else { return [NSRange(location: 0, length: 0)] }

        var ranges: [NSRange] = []
        var location = 0
        var safety = 0

        while location < total, safety < 50000 {
            safety += 1
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            container.lineBreakMode = .byTruncatingTail
            layoutManager.addTextContainer(container)

            let glyphRange = layoutManager.glyphRange(for: container)
            var charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

            if charRange.length == 0 {
                charRange = NSRange(location: location, length: min(total - location, 200))
            }
            ranges.append(charRange)

            let next = NSMaxRange(charRange)
            if next <= location { break }
            location = next
        }

        if ranges.isEmpty { ranges = [NSRange(location: 0, length: total)] }
        return ranges
    }

    /// 字符偏移 -> 页码
    static func pageIndex(of offset: Int, in ranges: [NSRange]) -> Int {
        guard !ranges.isEmpty else { return 0 }
        var low = 0, high = ranges.count - 1, result = 0
        while low <= high {
            let mid = (low + high) / 2
            if ranges[mid].location <= offset {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
