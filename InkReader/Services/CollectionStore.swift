//  墨阅 InkReader · InkReader/Services/CollectionStore.swift
//  功能：收藏夹仓库 —— 新建、重命名、改颜色、删除、批量移入移出书籍。
//  要点：增删成员只动 id 集合，不动书籍本体。

import Foundation
import SwiftUI

/// 收藏夹仓库。书架里的书只存 collectionIds，收藏夹自己单独一份 collections.json，
/// 这样删掉一个收藏夹不会动到书，书删了也只需要在各处摘掉它的 id。
final class CollectionStore: ObservableObject {
    @Published var collections: [BookCollection] = []

    init() {
        Storage.ensureDirectories()
        load()
    }

    // MARK: - 持久化

    func load() {
        guard let data = try? Data(contentsOf: Storage.collectionsFile),
              let decoded = try? JSONDecoder().decode([BookCollection].self, from: data)
        else { return }
        collections = decoded
        normalizeOrder()
    }

    func save() {
        if let data = try? JSONEncoder().encode(collections) {
            try? data.write(to: Storage.collectionsFile, options: .atomic)
        }
    }

    /// 修一遍 order：同级的序号压成 0,1,2…，避免删完之后出现空档
    private func normalizeOrder() {
        for parent in [nil as UUID?] + collections.map({ Optional($0.id) }) {
            let siblings = collections
                .filter { $0.parentId == parent }
                .sorted { lhs, rhs in
                    lhs.order == rhs.order ? lhs.createdAt < rhs.createdAt : lhs.order < rhs.order
                }
            for (idx, item) in siblings.enumerated() {
                if let i = collections.firstIndex(where: { $0.id == item.id }) {
                    collections[i].order = idx
                }
            }
        }
    }

    // MARK: - 增删改

    @discardableResult
    func create(name: String, colorHex: String? = nil, parentId: UUID? = nil) -> BookCollection {
        let trimmed = name.trimmed.isEmpty ? "新建收藏夹" : name.trimmed
        let siblings = collections.filter { $0.parentId == parentId }
        let nextOrder = (siblings.map { $0.order }.max() ?? -1) + 1
        let palette = BookCollection.palette
        let color = colorHex ?? palette[siblings.count % palette.count]
        let item = BookCollection(name: trimmed, colorHex: color, order: nextOrder, parentId: parentId)
        collections.append(item)
        save()
        return item
    }

    func rename(_ id: UUID, to name: String) {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmed
        collections[idx].name = trimmed.isEmpty ? collections[idx].name : trimmed
        save()
    }

    func setColor(_ id: UUID, hex: String) {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[idx].colorHex = hex
        save()
    }

    func move(_ id: UUID, toParent parentId: UUID?) {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        // 不能挂到自己或自己的子孙下面，否则整棵树循环
        if let parentId, collections.descendants(of: id).contains(parentId) { return }
        collections[idx].parentId = parentId
        collections[idx].order = (collections.filter { $0.parentId == parentId }.map { $0.order }.max() ?? -1) + 1
        normalizeOrder()
        save()
    }

    /// 同级里往后/往前挪一位
    func shift(_ id: UUID, by delta: Int) {
        guard let item = collections.collection(withId: id) else { return }
        let siblings = collections
            .filter { $0.parentId == item.parentId }
            .sorted { $0.order < $1.order }
        guard let from = siblings.firstIndex(where: { $0.id == id }) else { return }
        let to = from + delta
        guard to >= 0, to < siblings.count else { return }
        var reordered = siblings
        reordered.swapAt(from, to)
        for (idx, element) in reordered.enumerated() {
            if let i = collections.firstIndex(where: { $0.id == element.id }) {
                collections[i].order = idx
            }
        }
        save()
    }

    /// 删收藏夹本身。书都保留，只是从这些收藏夹里摘出去（由调用方把 ids 传回给 LibraryStore）。
    /// - Returns: 被删掉的（含子夹）id 集合
    @discardableResult
    func delete(_ id: UUID) -> Set<UUID> {
        let ids = Set(collections.descendants(of: id))
        collections.removeAll { ids.contains($0.id) }
        normalizeOrder()
        save()
        return ids
    }

    /// 清空某个收藏夹里的书（收藏夹自己还在）
    /// - Returns: 需要从书上摘掉的收藏夹 id 集合
    func clear(_ id: UUID) -> Set<UUID> {
        Set(collections.descendants(of: id))
    }

    // MARK: - 查询

    func collection(withId id: UUID) -> BookCollection? {
        collections.collection(withId: id)
    }

    var topLevel: [BookCollection] { collections.topLevel }
    func children(of id: UUID) -> [BookCollection] { collections.children(of: id) }

    func displayName(of id: UUID) -> String {
        collections.displayName(of: id)
    }

    /// 用于侧栏展示的数量统计（只数直接归属，不往上汇总）
    func count(books: [Book], in id: UUID) -> Int {
        books.filter { $0.collectionIds.contains(id) }.count
    }
}
