//  墨阅 InkReader · InkReader/Views/Library/LibrarySidebarView.swift
//  功能：书架侧栏 —— 全部 / 各收藏夹 / 按格式筛选，并承载批量选择入口。
//  要点：LibraryFilter 与 SidebarItem 只在这里定义。

import SwiftUI

/// 书架侧栏的筛选项。iPad 上常驻在左边一栏（NavigationSplitView 的 sidebar），
/// iPhone 上会退化成一个普通的列表页。
enum LibraryFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case reading
    case favorite
    case text
    case pdf
    case comic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .reading: return "在读"
        case .favorite: return "收藏"
        case .text: return "文本小说"
        case .pdf: return "PDF"
        case .comic: return "漫画"
        }
    }

    var icon: String {
        switch self {
        case .all: return "books.vertical"
        case .reading: return "book"
        case .favorite: return "heart"
        case .text: return "doc.plaintext"
        case .pdf: return "doc.richtext"
        case .comic: return "photo.stack"
        }
    }

    /// 属于「分类」这一组（在侧栏里和「书库」分开显示）
    var isCategory: Bool {
        switch self {
        case .text, .pdf, .comic: return true
        default: return false
        }
    }

    func matches(_ book: Book) -> Bool {
        switch self {
        case .all: return true
        case .reading: return book.progress > 0.005 && book.progress < 0.995
        case .favorite: return book.isFavorite
        case .text: return book.format == .txt || book.format == .epub
        case .pdf: return book.format == .pdf
        case .comic: return book.format == .comic
        }
    }
}

/// 侧栏选中项：要么是内置筛选，要么是某个收藏夹
enum SidebarItem: Hashable {
    case filter(LibraryFilter)
    case collection(UUID)

    static let all = SidebarItem.filter(.all)
}

struct LibrarySidebarView: View {
    @Binding var selection: SidebarItem
    let collections: CollectionStore
    let counts: [LibraryFilter: Int]
    let totalCount: Int
    let totalSizeDescription: String
    let bookCountIn: (UUID) -> Int
    let onManageCollections: () -> Void

    var body: some View {
        // iOS 上只有 List(selection: Binding<SelectionValue?>) 这个重载，
        // 非 optional 那版是 macOS 独有的（编译器直接标了 unavailable in iOS），
        // 所以这里包一层 optional 绑定。
        List(selection: optionalSelection) {
            Section("书库") {
                row(.filter(.all), title: "全部", icon: "books.vertical", count: totalCount)
                row(.filter(.reading), title: LibraryFilter.reading.title, icon: LibraryFilter.reading.icon, count: counts[.reading] ?? 0)
                row(.filter(.favorite), title: LibraryFilter.favorite.title, icon: LibraryFilter.favorite.icon, count: counts[.favorite] ?? 0)
            }
            Section("分类") {
                row(.filter(.text), title: LibraryFilter.text.title, icon: LibraryFilter.text.icon, count: counts[.text] ?? 0)
                row(.filter(.pdf), title: LibraryFilter.pdf.title, icon: LibraryFilter.pdf.icon, count: counts[.pdf] ?? 0)
                row(.filter(.comic), title: LibraryFilter.comic.title, icon: LibraryFilter.comic.icon, count: counts[.comic] ?? 0)
            }
            Section {
                ForEach(flattened, id: \.collection.id) { item in
                    collectionRow(item)
                }
                Button(action: onManageCollections) {
                    Label("管理收藏夹", systemImage: "folder.badge.gearshape")
                        .font(.subheadline)
                }
            } header: {
                Text("收藏夹")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("墨阅")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(totalCount) 本 · 本地存储")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !totalSizeDescription.isEmpty {
                    Text(totalSizeDescription)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - 行

    private var optionalSelection: Binding<SidebarItem?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue { selection = newValue }
            }
        )
    }

    @ViewBuilder
    private func row(_ item: SidebarItem, title: String, icon: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .tag(item)
    }

    private func collectionRow(_ item: (collection: BookCollection, depth: Int)) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.depth > 0 ? "folder" : "folder.fill")
                .font(.caption)
                .foregroundStyle(Color(hex: item.collection.colorHex))
            Text(item.collection.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(bookCountIn(item.collection.id))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.leading, CGFloat(item.depth) * 14)
        .tag(SidebarItem.collection(item.collection.id))
    }

    // MARK: - 嵌套展平

    /// 侧栏不做折叠树（List + selection 下 DisclosureGroup 容易点不动），
    /// 直接按层级缩进铺平，最多 4 层。
    private var flattened: [(collection: BookCollection, depth: Int)] {
        var result: [(BookCollection, Int)] = []
        func walk(parent: UUID?, depth: Int) {
            guard depth < 4 else { return }
            let kids = parent == nil ? collections.topLevel : collections.children(of: parent!)
            for kid in kids {
                result.append((kid, depth))
                walk(parent: kid.id, depth: depth + 1)
            }
        }
        walk(parent: nil, depth: 0)
        return result
    }
}
