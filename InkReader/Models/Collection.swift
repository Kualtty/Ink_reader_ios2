//  墨阅 InkReader · InkReader/Models/Collection.swift
//  功能：收藏夹模型 —— BookCollection（名称 / 颜色 / 成员 bookId 集合）。
//  要点：只存 id 不存书籍对象，避免和书架数据不同步。

import Foundation
import SwiftUI

/// 收藏夹。支持重命名 / 12 种配色 / 手动排序 / 一层嵌套（parentId）。
struct BookCollection: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// 封面/标签色，#RRGGBB
    var colorHex: String = BookCollection.defaultColorHex
    /// 同级排序，小的在前
    var order: Int = 0
    /// 父收藏夹，nil = 顶层
    var parentId: UUID?
    var createdAt: Date = Date()

    static let defaultColorHex = "#2E5A88"

    /// 12 种预置配色（和 Web 原型保持一致）
    static let palette: [String] = [
        "#2E5A88", "#C0392B", "#27865A", "#B7791F",
        "#6D4FA3", "#0E7490", "#A03E6F", "#4B5563",
        "#936F3B", "#2F6F8F", "#7A5548", "#3F6B35"
    ]

    var color: Color { Color(hex: colorHex) }

    enum CodingKeys: String, CodingKey {
        case id, name, colorHex, order, parentId, createdAt
    }

    /// 同样是容忍型解码：缺字段补默认值，别让老存档炸掉
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "未命名"
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? BookCollection.defaultColorHex
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        parentId = try c.decodeIfPresent(UUID.self, forKey: .parentId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    init(name: String, colorHex: String = BookCollection.defaultColorHex, order: Int = 0, parentId: UUID? = nil) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.order = order
        self.parentId = parentId
        self.createdAt = Date()
    }
}

// MARK: - 嵌套辅助

extension Array where Element == BookCollection {
    /// 顶层收藏夹，按 order 排
    var topLevel: [BookCollection] {
        filter { $0.parentId == nil }.sorted { lhs, rhs in
            lhs.order == rhs.order ? lhs.createdAt < rhs.createdAt : lhs.order < rhs.order
        }
    }

    /// 某个收藏夹的直接子夹
    func children(of id: UUID) -> [BookCollection] {
        filter { $0.parentId == id }.sorted { lhs, rhs in
            lhs.order == rhs.order ? lhs.createdAt < rhs.createdAt : lhs.order < rhs.order
        }
    }

    func collection(withId id: UUID) -> BookCollection? {
        first { $0.id == id }
    }

    /// 含自身在内的整棵子树的 id（删收藏夹时用它连同子夹一起处理）
    func descendants(of id: UUID) -> [UUID] {
        var result: [UUID] = [id]
        var frontier: [UUID] = [id]
        while let current = frontier.popLast() {
            let kids = filter { $0.parentId == current }.map { $0.id }
            result.append(contentsOf: kids)
            frontier.append(contentsOf: kids)
        }
        return result
    }

    /// 展示用的全名，带层级：「漫画 / 日漫」
    func displayName(of id: UUID) -> String {
        var chain: [String] = []
        var cursor: UUID? = id
        var guardCount = 0
        while let current = cursor, guardCount < 10 {
            guard let item = collection(withId: current) else { break }
            chain.insert(item.name, at: 0)
            cursor = item.parentId
            guardCount += 1
        }
        return chain.joined(separator: " / ")
    }
}
