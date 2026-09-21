//  墨阅 InkReader · InkReader/Views/Library/ComicPagesView.swift
//  功能：漫画页面管理 —— 缩略图列表、拖动排序、删页、从某页拆开、合入另一本漫画。
//  要点：缩略图走 ThumbCache（NSCache）；改完页序一定要调用 remapPages 搬迁标注。

import SwiftUI
import UIKit

/// 漫画页面管理：排序、删页、拆分、合并
///
/// 页号一动，书签 / 笔记 / 涂鸦都得跟着搬 —— 这里是按「旧页号 → 新页号」映射搬的，
/// 所以合并拆分不会再像早期版本那样把批注全丢了。
struct ComicPagesView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var annotations: AnnotationStore
    @EnvironmentObject private var pages: ComicPageStore
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var paths: [String] = []
    @State private var items: [URL] = []
    @State private var alertMessage: String?
    @State private var showMerge = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showMerge = true
                    } label: {
                        Label("合并另一本漫画到这本", systemImage: "arrow.triangle.merge")
                    }
                    Text("被合并的那本会从书架移除，它的书签、笔记、涂鸦按页号平移过来，一条都不删。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("共 \(items.count) 页") {
                    ForEach(0..<items.count, id: \.self) { index in
                        pageRow(url: items[index], index: index)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: remove)
                }

                Section {
                    Text("拖动排序 / 左滑删页：点右上角「编辑」，拖手柄改顺序，红色减号删页。"
                         + "删页和排序都会把这一页的书签笔记跟着挪走。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onAppear(perform: load)
        .sheet(isPresented: $showMerge) {
            mergePicker
        }
        .alert("提示", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - 行

    private func pageRow(url: URL, index: Int) -> some View {
        HStack(spacing: 12) {
            thumbnail(url)
                .frame(width: 54, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text("第 \(index + 1) 页")
                    .font(.subheadline)
                Text(url.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if annotations.bookmarks.contains(where: { $0.bookId == book.id && $0.page == index })
                || annotations.notes.contains(where: { $0.bookId == book.id && $0.page == index }) {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button("从这页拆开") { split(at: index) }
                .font(.caption)
                .buttonStyle(.bordered)
                .disabled(index == 0)
        }
    }

    private func thumbnail(_ url: URL) -> some View {
        Group {
            if let image = ThumbCache.shared.image(at: url) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
    }

    // MARK: - 合并

    private var otherComics: [Book] {
        library.books.filter { $0.format == .comic && $0.id != book.id }
    }

    private var mergePicker: some View {
        NavigationStack {
            List {
                if otherComics.isEmpty {
                    Text("书架上没有别的漫画可以合并")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(otherComics) { other in
                        Button {
                            merge(other)
                        } label: {
                            HStack {
                                Image(systemName: other.format.symbolName)
                                Text(other.title)
                                Spacer()
                                Text("\(other.totalPages) 页")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("合并哪一本？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showMerge = false }
                }
            }
        }
    }

    // MARK: - 动作

    private func load() {
        // 没存过顺序就先按解压顺序固化一份，后面拖排序才有基准
        if pages.orders[book.id] == nil {
            pages.setOrder(pages.relativePaths(for: book), for: book.id)
        }
        reload()
    }

    private func reload() {
        paths = pages.relativePaths(for: book)
        items = pages.pages(for: book)
        if var copy = library.book(withId: book.id), copy.totalPages != items.count {
            copy.totalPages = items.count
            library.update(copy)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        let before = paths
        var next = before
        next.move(fromOffsets: source, toOffset: destination)
        pages.setOrder(next, for: book.id)
        annotations.remapPages(bookId: book.id, mapping: pages.mapping(from: before, to: next))
        reload()
    }

    private func remove(at offsets: IndexSet) {
        let mapping = pages.removePages(bookId: book.id, at: offsets)
        annotations.remapPages(bookId: book.id, mapping: mapping)
        reload()
    }

    private func split(at index: Int) {
        guard let current = library.book(withId: book.id) else { return }
        do {
            let created = try pages.split(
                current,
                at: index,
                library: library,
                annotations: annotations
            )
            alertMessage = "已拆出「\(created.title)」，共 \(created.totalPages) 页"
            reload()
        } catch {
            alertMessage = "拆分失败：\(error.localizedDescription)"
        }
    }

    private func merge(_ other: Book) {
        guard let current = library.book(withId: book.id) else { return }
        do {
            let merged = try pages.merge(
                other,
                into: current,
                library: library,
                annotations: annotations
            )
            showMerge = false
            alertMessage = "已合并，现在共 \(merged.totalPages) 页"
            reload()
        } catch {
            alertMessage = "合并失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 缩略图缓存

/// 一本漫画几百页，全尺寸解码一遍内存就爆了：这里按路径缓存 140px 宽的小图
private final class ThumbCache {
    static let shared = ThumbCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(at url: URL) -> UIImage? {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let raw = UIImage(contentsOfFile: url.path), raw.size.width > 0 else { return nil }
        let ratio = min(1, 140 / max(1, raw.size.width))
        let size = CGSize(width: raw.size.width * ratio, height: raw.size.height * ratio)
        let small = UIGraphicsImageRenderer(size: size).image { _ in
            raw.draw(in: CGRect(origin: .zero, size: size))
        }
        cache.setObject(small, forKey: key)
        return small
    }
}
