import Foundation

// MARK: - 书籍格式

enum BookFormat: String, Codable, CaseIterable, Identifiable {
    case txt
    case epub
    case pdf
    case comic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .txt: return "TXT"
        case .epub: return "EPUB"
        case .pdf: return "PDF"
        case .comic: return "漫画"
        }
    }

    var symbolName: String {
        switch self {
        case .txt: return "doc.plaintext"
        case .epub: return "book.closed"
        case .pdf: return "doc.richtext"
        case .comic: return "photo.stack"
        }
    }

    /// 是否是纯文字排版（需要字体/分栏/分页引擎）
    var isReflowable: Bool {
        switch self {
        case .txt, .epub: return true
        case .pdf, .comic: return false
        }
    }

    init?(fileExtension ext: String) {
        switch ext.lowercased() {
        case "txt", "text", "md": self = .txt
        case "epub": self = .epub
        case "pdf": self = .pdf
        case "cbz", "zip", "cbr": self = .comic
        case "jpg", "jpeg", "png", "webp", "heic", "gif", "bmp": self = .comic
        default: return nil
        }
    }

    static var importableExtensions: [String] {
        ["txt", "text", "md", "epub", "pdf", "cbz", "zip", "jpg", "jpeg", "png", "webp", "heic"]
    }
}

// MARK: - 封面模式

/// 书架卡片封面怎么显示：缩略图 / 纯色 / 自定义图片
enum BookCoverMode: String, Codable, CaseIterable, Identifiable {
    case thumb
    case color
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thumb: return "内容缩略图"
        case .color: return "纯色封面"
        case .image: return "自定义图片"
        }
    }

    var symbolName: String {
        switch self {
        case .thumb: return "doc.text.image"
        case .color: return "square.fill"
        case .image: return "photo"
        }
    }
}

// MARK: - 书籍

struct Book: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var author: String = ""
    var format: BookFormat
    /// 存放在 Documents/Books 下的文件名
    var fileName: String
    /// 封面图片文件名（Documents/Covers）
    var coverFileName: String?
    var addedAt: Date = Date()
    var lastReadAt: Date?
    /// 阅读位置：TXT/EPUB = 全局字符偏移；PDF/漫画 = 页码索引
    var locator: String = "0"
    var progress: Double = 0
    var totalPages: Int = 0
    var fileSize: Int64 = 0
    var isFavorite: Bool = false
    /// 每本书单独的翻页方向覆盖（nil = 跟随全局）
    var directionRaw: String?
    /// 所属收藏夹（iOS 17 上多选归属，一本书可以在多个收藏夹里）
    var collectionIds: [UUID] = []
    /// 封面模式，nil = 跟随内容自动生成
    var coverModeRaw: String?
    /// 自定义封面时，纯色的十六进制色值（#RRGGBB）
    var coverColorHex: String?

    var fileURL: URL {
        Storage.booksDirectory.appendingPathComponent(fileName)
    }

    var coverURL: URL? {
        guard let name = coverFileName else { return nil }
        return Storage.coversDirectory.appendingPathComponent(name)
    }

    var direction: PageTurnDirection? {
        get { directionRaw.flatMap { PageTurnDirection(rawValue: $0) } }
        set { directionRaw = newValue?.rawValue }
    }

    var coverMode: BookCoverMode? {
        get { coverModeRaw.flatMap { BookCoverMode(rawValue: $0) } }
        set { coverModeRaw = newValue?.rawValue }
    }

    /// 页码（1 开始）
    var pageNumber: Int {
        (Int(locator) ?? 0) + 1
    }
}

// MARK: - 容忍型解码
//
// 这里不直接用编译器合成的 Decodable：历史存档里没有 collectionIds / coverModeRaw
// 这些新字段，合成版会直接 throw，整本 library.json 读不出来 = 用户书架全没。
// 改成逐个 decodeIfPresent，缺哪个就用默认值补上。
//
// ⚠️ 必须写在 extension 里：写在 struct 本体会让编译器不再生成成员逐一
// 初始化器 Book(id:title:format:…)，而 BookImporter 全靠它造书。

extension Book {
    private enum CodingKeys: String, CodingKey {
        case id, title, author, format, fileName, coverFileName, addedAt, lastReadAt
        case locator, progress, totalPages, fileSize, isFavorite, directionRaw
        case collectionIds, coverModeRaw, coverColorHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        format = try c.decodeIfPresent(BookFormat.self, forKey: .format) ?? .txt
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        coverFileName = try c.decodeIfPresent(String.self, forKey: .coverFileName)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        lastReadAt = try c.decodeIfPresent(Date.self, forKey: .lastReadAt)
        locator = Self.decodeLocator(c)
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        totalPages = try c.decodeIfPresent(Int.self, forKey: .totalPages) ?? 0
        fileSize = try c.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        directionRaw = try c.decodeIfPresent(String.self, forKey: .directionRaw)
        collectionIds = try c.decodeIfPresent([UUID].self, forKey: .collectionIds) ?? []
        coverModeRaw = try c.decodeIfPresent(String.self, forKey: .coverModeRaw)
        coverColorHex = try c.decodeIfPresent(String.self, forKey: .coverColorHex)
    }

    /// 老版本把 locator 存成过数字，这里两种都接
    private static func decodeLocator(_ c: KeyedDecodingContainer<CodingKeys>) -> String {
        if let s = try? c.decodeIfPresent(String.self, forKey: .locator) { return s }
        if let i = try? c.decodeIfPresent(Int.self, forKey: .locator) { return String(i) }
        if let d = try? c.decodeIfPresent(Double.self, forKey: .locator) { return String(Int(d)) }
        return "0"
    }
}

// MARK: - 章节

struct Chapter: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    /// 在全文中的字符偏移
    var offset: Int
    var level: Int = 0

    init(title: String, offset: Int, level: Int = 0) {
        self.id = UUID()
        self.title = title
        self.offset = offset
        self.level = level
    }
}
