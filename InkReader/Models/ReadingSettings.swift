//  墨阅 InkReader · InkReader/Models/ReadingSettings.swift
//  功能：阅读设置 —— 主题、字号、行距、对齐、翻页方向、漫画阅读模式与方向、自动翻页速度。
//  要点：全局一份，改动即落盘；文字阅读器与漫画阅读器共用同一份设置。

import SwiftUI
import UIKit

// MARK: - 翻页方向

enum PageTurnDirection: String, Codable, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal: return "左右翻页"
        case .vertical: return "上下翻页"
        }
    }

    var shortTitle: String {
        switch self {
        case .horizontal: return "左右"
        case .vertical: return "上下"
        }
    }

    var icon: String {
        switch self {
        case .horizontal: return "arrow.left.and.right"
        case .vertical: return "arrow.up.and.down"
        }
    }
}

// MARK: - 漫画阅读形态（与文字书的「左右/上下」互相独立）

/// 分页 = 一页一页翻；连续卷轴 = 整本摊成一条长列往下滚（条漫 / webtoon）
enum ComicReadMode: String, Codable, CaseIterable, Identifiable {
    case paged
    case scroll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paged: return "分页"
        case .scroll: return "连续卷轴"
        }
    }

    var icon: String {
        switch self {
        case .paged: return "doc.text.image"
        case .scroll: return "rectangle.grid.1x2"
        }
    }
}

/// 漫画翻页方向三选。
/// - ltr：左→右（欧美漫画，默认）
/// - rtl：右→左（日漫）
/// - ttb：上→下（条漫 / 卷轴，等同于 comicMode = .scroll）
enum ComicDirection: String, Codable, CaseIterable, Identifiable {
    case ltr
    case rtl
    case ttb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ltr: return "左→右"
        case .rtl: return "右→左（日漫）"
        case .ttb: return "上→下（卷轴）"
        }
    }

    var shortTitle: String {
        switch self {
        case .ltr: return "左右"
        case .rtl: return "右左"
        case .ttb: return "上下"
        }
    }

    var icon: String {
        switch self {
        case .ltr: return "arrow.left.and.right"
        case .rtl: return "arrow.right.and.left"
        case .ttb: return "arrow.up.and.down"
        }
    }

    /// 底栏按钮点一下切到下一个方向：左→右 → 右→左 → 上→下 → 左→右
    var next: ComicDirection {
        switch self {
        case .ltr: return .rtl
        case .rtl: return .ttb
        case .ttb: return .ltr
        }
    }
}

// MARK: - 主题

enum ReaderTheme: String, Codable, CaseIterable, Identifiable {
    case paper
    case cream
    case green
    case gray
    case night
    case pureBlack
    case custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .paper: return "纯白"
        case .cream: return "米黄"
        case .green: return "护眼绿"
        case .gray: return "淡灰"
        case .night: return "夜间"
        case .pureBlack: return "纯黑"
        case .custom: return "自定义"
        }
    }

    var defaultBackgroundHex: String {
        switch self {
        case .paper: return "#FFFFFF"
        case .cream: return "#F5ECD7"
        case .green: return "#C9E7C8"
        case .gray: return "#E9E9EB"
        case .night: return "#2C2C2E"
        case .pureBlack: return "#000000"
        case .custom: return "#F3E9D2"
        }
    }

    var defaultForegroundHex: String {
        switch self {
        case .paper: return "#1A1A1A"
        case .cream: return "#4A3F2F"
        case .green: return "#1E3A24"
        case .gray: return "#3A3A3C"
        case .night: return "#D8D8DC"
        case .pureBlack: return "#8E8E93"
        case .custom: return "#2E2A24"
        }
    }

    var isDark: Bool {
        switch self {
        case .night, .pureBlack: return true
        default: return false
        }
    }
}

// MARK: - 对齐

enum TextAlignOption: String, Codable, CaseIterable, Identifiable {
    case justified
    case leading
    case center

    var id: String { rawValue }

    var name: String {
        switch self {
        case .justified: return "两端对齐"
        case .leading: return "左对齐"
        case .center: return "居中"
        }
    }

    var textAlignment: NSTextAlignment {
        switch self {
        case .justified: return .justified
        case .leading: return .left
        case .center: return .center
        }
    }
}

// MARK: - 阅读设置

struct ReadingSettings: Codable, Equatable {
    // 排版
    var fontSize: CGFloat = 19
    var lineSpacing: CGFloat = 9
    var characterSpacing: CGFloat = 0.6
    var paragraphSpacing: CGFloat = 14
    var fontName: String = ""
    var isBold: Bool = false
    var alignment: TextAlignOption = .justified
    var horizontalMargin: CGFloat = 22
    var verticalMargin: CGFloat = 26

    // 外观
    var theme: ReaderTheme = .paper
    var customBackgroundHex: String = "#F3E9D2"
    var customForegroundHex: String = "#2E2A24"

    // 行为
    var direction: PageTurnDirection = .horizontal
    var autoPlaySpeed: Double = 8          // 秒 / 页（或秒 / 屏）
    var keepScreenOn: Bool = true
    var volumeKeyTurn: Bool = false
    var doublePageSpread: Bool = false     // 横屏双页（PDF / 漫画）
    var showPageIndicator: Bool = true
    var tapToTurnPage: Bool = false        // 点击屏幕边缘翻页

    // 播读（TTS）
    var speechRate: Double = 0.5           // AVSpeechUtterance.rate，0~1，0.5 ≈ 正常语速
    var speechVoiceId: String = ""         // 语音标识符，空 = 自动挑

    // 漫画（只影响漫画，与文字书的 direction 互不干扰）
    var comicMode: ComicReadMode = .paged  // 分页 / 连续卷轴
    var comicRTL: Bool = false             // 右→左（日漫）

    // MARK: 派生值

    /// 漫画翻页方向。三向是「形态 + 左右」两个字段推导出来的，
    /// 这样存盘格式不用变（老版本只有 direction），设置面板也能分开给开关。
    var comicDirection: ComicDirection {
        get {
            if comicMode == .scroll { return .ttb }
            return comicRTL ? .rtl : .ltr
        }
        set {
            switch newValue {
            case .ltr: comicMode = .paged; comicRTL = false
            case .rtl: comicMode = .paged; comicRTL = true
            case .ttb: comicMode = .scroll; comicRTL = false
            }
        }
    }

    /// 漫画当前是不是连续卷轴
    var comicIsScroll: Bool { comicMode == .scroll }

    var backgroundHex: String {
        theme == .custom ? customBackgroundHex : theme.defaultBackgroundHex
    }

    var foregroundHex: String {
        theme == .custom ? customForegroundHex : theme.defaultForegroundHex
    }

    var backgroundColor: Color {
        Color(hex: backgroundHex)
    }

    var textColor: Color {
        Color(hex: foregroundHex)
    }

    var uiBackgroundColor: UIColor {
        UIColor(hex: backgroundHex)
    }

    var uiTextColor: UIColor {
        UIColor(hex: foregroundHex)
    }

    var preferredStatusBarStyle: UIUserInterfaceStyle {
        theme.isDark ? .dark : .light
    }

    /// 正文字体
    var uiFont: UIFont {
        let size = fontSize
        if fontName.isEmpty {
            return isBold
                ? UIFont.boldSystemFont(ofSize: size)
                : UIFont.systemFont(ofSize: size)
        }
        if let custom = UIFont(name: fontName, size: size) {
            return isBold ? (custom.boldVariant ?? custom) : custom
        }
        return isBold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
    }

    /// 段落样式
    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.alignment = alignment.textAlignment
        style.firstLineHeadIndent = 0
        style.hyphenationFactor = alignment == .justified ? 0.8 : 0
        return style
    }

    /// 正文富文本属性
    var baseAttributes: [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: uiFont,
            .foregroundColor: uiTextColor,
            .paragraphStyle: paragraphStyle,
            .kern: characterSpacing
        ]
        if #available(iOS 16.0, *) {
            // 保持系统字体的字距特性
        }
        return attrs
    }

    /// 标题属性（章节名）
    var titleAttributes: [NSAttributedString.Key: Any] {
        var attrs = baseAttributes
        attrs[.font] = UIFont.boldSystemFont(ofSize: fontSize + 6)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacingBefore = paragraphSpacing * 1.5
        style.paragraphSpacing = paragraphSpacing
        style.alignment = .left
        attrs[.paragraphStyle] = style
        return attrs
    }

    /// 内容区域尺寸（用于分页）
    func contentSize(in viewSize: CGSize) -> CGSize {
        CGSize(
            width: max(40, viewSize.width - horizontalMargin * 2),
            height: max(60, viewSize.height - verticalMargin * 2)
        )
    }
}

// MARK: - 编解码（必须容错：老存档缺字段时不能把整个设置丢掉）

extension ReadingSettings {
    /// 注意：Swift 合成的 Decodable 在 key 缺失时会直接 throw，
    /// 那样旧版本存档（还没有 comicMode / comicRTL）一升级就会被判为损坏，
    /// 用户的字体、主题、进度全丢。所以这里显式实现，每个字段都给默认值。
    /// ⚠️ 以后新增字段务必同步加到这里，否则新字段读出来永远是默认值。
    private enum CodingKeys: String, CodingKey {
        case fontSize, lineSpacing, characterSpacing, paragraphSpacing
        case fontName, isBold, alignment
        case horizontalMargin, verticalMargin
        case theme, customBackgroundHex, customForegroundHex
        case direction, autoPlaySpeed, keepScreenOn, volumeKeyTurn
        case doublePageSpread, showPageIndicator, tapToTurnPage
        case comicMode, comicRTL
        case speechRate, speechVoiceId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 19
        lineSpacing = try c.decodeIfPresent(CGFloat.self, forKey: .lineSpacing) ?? 9
        characterSpacing = try c.decodeIfPresent(CGFloat.self, forKey: .characterSpacing) ?? 0.6
        paragraphSpacing = try c.decodeIfPresent(CGFloat.self, forKey: .paragraphSpacing) ?? 14
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? ""
        isBold = try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        alignment = try c.decodeIfPresent(TextAlignOption.self, forKey: .alignment) ?? .justified
        horizontalMargin = try c.decodeIfPresent(CGFloat.self, forKey: .horizontalMargin) ?? 22
        verticalMargin = try c.decodeIfPresent(CGFloat.self, forKey: .verticalMargin) ?? 26

        theme = try c.decodeIfPresent(ReaderTheme.self, forKey: .theme) ?? .paper
        customBackgroundHex = try c.decodeIfPresent(String.self, forKey: .customBackgroundHex) ?? "#F3E9D2"
        customForegroundHex = try c.decodeIfPresent(String.self, forKey: .customForegroundHex) ?? "#2E2A24"

        direction = try c.decodeIfPresent(PageTurnDirection.self, forKey: .direction) ?? .horizontal
        autoPlaySpeed = try c.decodeIfPresent(Double.self, forKey: .autoPlaySpeed) ?? 8
        keepScreenOn = try c.decodeIfPresent(Bool.self, forKey: .keepScreenOn) ?? true
        volumeKeyTurn = try c.decodeIfPresent(Bool.self, forKey: .volumeKeyTurn) ?? false
        doublePageSpread = try c.decodeIfPresent(Bool.self, forKey: .doublePageSpread) ?? false
        showPageIndicator = try c.decodeIfPresent(Bool.self, forKey: .showPageIndicator) ?? true
        tapToTurnPage = try c.decodeIfPresent(Bool.self, forKey: .tapToTurnPage) ?? false

        comicMode = try c.decodeIfPresent(ComicReadMode.self, forKey: .comicMode) ?? .paged
        comicRTL = try c.decodeIfPresent(Bool.self, forKey: .comicRTL) ?? false

        speechRate = try c.decodeIfPresent(Double.self, forKey: .speechRate) ?? 0.5
        speechVoiceId = try c.decodeIfPresent(String.self, forKey: .speechVoiceId) ?? ""
    }
}

// MARK: - 可用字体列表

enum ReaderFonts {
    static let available: [(name: String, display: String)] = {
        var list: [(String, String)] = [("", "系统默认")]
        let preferred = [
            "PingFang SC", "Songti SC", "STSong", "Kaiti SC", "STKaiti",
            "Heiti SC", "Yuanti SC", "Hiragino Sans GB",
            "Times New Roman", "Georgia", "Helvetica Neue", "Avenir Next",
            "Menlo", "Courier New"
        ]
        for name in preferred {
            if UIFont(name: name, size: 16) != nil {
                list.append((name, name))
            }
        }
        // 补充系统已安装字体
        for family in UIFont.familyNames.sorted() {
            for font in UIFont.fontNames(forFamilyName: family) {
                if !list.contains(where: { $0.name == font }),
                   let ui = UIFont(name: font, size: 16),
                   ui.fontDescriptor.symbolicTraits.contains(.traitBold) == false {
                    // 只挑选常见中文/西文字体，避免列表过长
                    if font.hasPrefix("PingFang") || font.hasPrefix("Songti")
                        || font.hasPrefix("Kaiti") || font.hasPrefix("Yuanti")
                        || font.hasPrefix("ST") || font.hasPrefix("Hiragino") {
                        list.append((font, font))
                    }
                }
            }
        }
        return list
    }()
}

private extension UIFont {
    var boldVariant: UIFont? {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return nil }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
