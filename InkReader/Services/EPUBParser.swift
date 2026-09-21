//  墨阅 InkReader · InkReader/Services/EPUBParser.swift
//  功能：EPUB 解析 —— container.xml → OPF → spine，拼出纯文本与章节列表。
//  要点：导入后按纯文本处理，所以 EPUB 也能用「编辑原文」修订。

import Foundation
import ZIPFoundation

/// 基础 EPUB 解析：解压 -> container.xml -> OPF -> spine -> 纯文本
/// 说明：为保证排版/分页/划词一致，EPUB 会被转成纯文本后按 TXT 引擎渲染。
enum EPUBParser {
    struct Result {
        var title: String
        var author: String
        var text: String
    }

    static func parse(url: URL) throws -> Result {
        guard let archive = Archive(url: url, accessMode: .read) else { throw ImportError.readFailed }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        // 1. container.xml
        guard let containerEntry = archive["META-INF/container.xml"] else { throw ImportError.readFailed }
        let containerURL = temp.appendingPathComponent("container.xml")
        _ = try archive.extract(containerEntry, to: containerURL)

        let containerParser = ContainerParser()
        if let parser = XMLParser(contentsOf: containerURL) {
            parser.delegate = containerParser
            parser.parse()
        }
        guard let opfPath = containerParser.opfPath else { throw ImportError.readFailed }

        // 2. OPF
        guard let opfEntry = archive[opfPath] else { throw ImportError.readFailed }
        let opfURL = temp.appendingPathComponent("content.opf")
        _ = try archive.extract(opfEntry, to: opfURL)

        let opfParser = OPFParser()
        if let parser = XMLParser(contentsOf: opfURL) {
            parser.delegate = opfParser
            parser.parse()
        }

        let base = (opfPath as NSString).deletingLastPathComponent

        // 3. spine 顺序拼接正文
        var text = ""
        for idref in opfParser.spine {
            guard let href = opfParser.manifest[idref] else { continue }
            let fullPath = base.isEmpty ? href : (base as NSString).appendingPathComponent(href)
            guard let entry = archive[fullPath] else { continue }
            let out = temp.appendingPathComponent("\(UUID().uuidString).xhtml")
            guard (try? archive.extract(entry, to: out)) != nil else { continue }
            guard let data = try? Data(contentsOf: out) else { continue }
            let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? String(decoding: data, as: UTF8.self)
            let plain = htmlToText(raw)
            if !plain.trimmed.isEmpty {
                text += plain + "\n\n"
            }
        }

        guard !text.trimmed.isEmpty else { throw ImportError.readFailed }

        let fallbackTitle = (url.lastPathComponent as NSString).deletingPathExtension
        return Result(
            title: opfParser.title?.trimmed.isEmpty == false ? opfParser.title!.trimmed : fallbackTitle,
            author: opfParser.author ?? "",
            text: text
        )
    }

    // MARK: - HTML 转纯文本

    static func htmlToText(_ html: String) -> String {
        var s = html
        let removals = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<!--[\\s\\S]*?-->"
        ]
        for pattern in removals {
            s = s.replacingOccurrences(
                of: pattern, with: "", options: [.regularExpression, .caseInsensitive]
            )
        }
        s = s.replacingOccurrences(
            of: "<(?:br|/p|/div|/h[1-6]|/li|/tr|p|div)[^>]*>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ input: String) -> String {
        var s = input
        let named: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&mdash;": "—",
            "&ndash;": "–", "&ldquo;": "“", "&rdquo;": "”", "&lsquo;": "‘",
            "&rsquo;": "’", "&hellip;": "…", "&middot;": "·"
        ]
        for (key, value) in named { s = s.replacingOccurrences(of: key, with: value) }

        // 数字实体 &#1234;
        if let regex = try? NSRegularExpression(pattern: "&#([0-9]+);", options: []) {
            let ns = s as NSString
            let matches = regex.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() where match.numberOfRanges > 1 {
                let numberRange = match.range(at: 1)
                guard let code = UInt32(ns.substring(with: numberRange)),
                      let scalar = Unicode.Scalar(code) else { continue }
                s = (s as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
            }
        }
        return s
    }
}

// MARK: - XML Delegate

private final class ContainerParser: NSObject, XMLParserDelegate {
    var opfPath: String?

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "rootfile", let path = attributeDict["full-path"] {
            opfPath = path
        }
    }
}

private final class OPFParser: NSObject, XMLParserDelegate {
    var title: String?
    var author: String?
    var manifest: [String: String] = [:]
    var spine: [String] = []

    private var currentElement = ""
    private var buffer = ""

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        buffer = ""
        if elementName == "item",
           let id = attributeDict["id"],
           let href = attributeDict["href"] {
            manifest[id] = href
        }
        if elementName == "itemref", let idref = attributeDict["idref"] {
            spine.append(idref)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            if elementName == "title" || elementName.hasSuffix(":title") { title = value }
            if (elementName == "creator" || elementName.hasSuffix(":creator")), author == nil {
                author = value
            }
        }
        buffer = ""
    }
}
