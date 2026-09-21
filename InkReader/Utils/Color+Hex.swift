//  墨阅 InkReader · InkReader/Utils/Color+Hex.swift
//  功能：颜色扩展 —— hex 字符串与 Color / UIColor 互转，另含 Data 的小扩展。
//  要点：封面配色、收藏夹颜色、主题色板都走这里。

import SwiftUI
import UIKit

extension Color {
    /// 支持 "#RGB" "#RRGGBB" "#AARRGGBB"
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var argb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&argb)

        let r, g, b, a: Double
        switch hexSanitized.count {
        case 3:
            r = Double((argb & 0xF00) >> 8) / 15
            g = Double((argb & 0x0F0) >> 4) / 15
            b = Double(argb & 0x00F) / 15
            a = 1
        case 6:
            r = Double((argb & 0xFF0000) >> 16) / 255
            g = Double((argb & 0x00FF00) >> 8) / 255
            b = Double(argb & 0x0000FF) / 255
            a = 1
        case 8:
            a = Double((argb & 0xFF000000) >> 24) / 255
            r = Double((argb & 0x00FF0000) >> 16) / 255
            g = Double((argb & 0x0000FF00) >> 8) / 255
            b = Double(argb & 0x000000FF) / 255
        default:
            r = 1; g = 1; b = 1; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255))
        )
    }
}

extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var argb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&argb)

        let r, g, b, a: CGFloat
        switch hexSanitized.count {
        case 3:
            r = CGFloat((argb & 0xF00) >> 8) / 15
            g = CGFloat((argb & 0x0F0) >> 4) / 15
            b = CGFloat(argb & 0x00F) / 15
            a = 1
        case 6:
            r = CGFloat((argb & 0xFF0000) >> 16) / 255
            g = CGFloat((argb & 0x00FF00) >> 8) / 255
            b = CGFloat(argb & 0x0000FF) / 255
            a = 1
        case 8:
            a = CGFloat((argb & 0xFF000000) >> 24) / 255
            r = CGFloat((argb & 0x00FF0000) >> 16) / 255
            g = CGFloat((argb & 0x0000FF00) >> 8) / 255
            b = CGFloat(argb & 0x000000FF) / 255
        default:
            r = 1; g = 1; b = 1; a = 1
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

extension Data {
    var uiImage: UIImage? { UIImage(data: self) }
}
