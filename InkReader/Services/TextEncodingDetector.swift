import Foundation

/// TXT 编码探测：兼容 UTF-8 / GBK / GB18030 / Big5 / UTF-16 / Latin1
enum TextEncodingDetector {
    private static let gb18030: String.Encoding = {
        let cf = CFStringEncodings.GB_18030_2000
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue)))
    }()

    private static let big5: String.Encoding = {
        let cf = CFStringEncodings.big5
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue)))
    }()

    static func decode(_ data: Data) -> String? {
        if let bom = detectBOM(data), let text = String(data: data, encoding: bom) {
            return normalize(text)
        }

        // UTF-8 优先，并做严格校验（中文小说常见的 GBK 会被 UTF-8 解析失败）
        if let text = String(data: data, encoding: .utf8), isValidRatio(text) {
            return normalize(text)
        }

        let candidates: [String.Encoding] = [gb18030, big5, .utf16, .isoLatin1]
        for encoding in candidates {
            if let text = String(data: data, encoding: encoding), isValidRatio(text) {
                return normalize(text)
            }
        }
        // 兜底
        return normalize(String(decoding: data, as: UTF8.self))
    }

    private static func detectBOM(_ data: Data) -> String.Encoding? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { return .utf8 }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE { return .utf16LittleEndian }
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF { return .utf16BigEndian }
        return nil
    }

    /// 检测是否含有大量替换字符（说明编码猜错了）
    private static func isValidRatio(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let sample = text.prefix(6000)
        let bad = sample.filter { $0 == "\u{FFFD}" }.count
        return Double(bad) / Double(sample.count) < 0.02
    }

    private static func normalize(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // 去掉 BOM 字符
        result = result.replacingOccurrences(of: "\u{FEFF}", with: "")
        // 章节前补空行，方便分段
        result = result.replacingOccurrences(
            of: "\n(?=\\s*第[0-9零一二三四五六七八九十百千两〇○]{1,8}[章节回卷篇部集])",
            with: "\n\n",
            options: .regularExpression
        )
        // 超过两个连续换行合并为两个
        result = result.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        // 行首行尾空白
        result = result.replacingOccurrences(
            of: "[ \t]+",
            with: " ",
            options: .regularExpression
        )
        return result
    }
}
