import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var annotations: AnnotationStore
    @EnvironmentObject private var collections: CollectionStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showImporter = false
    @State private var searchText = ""
    @State private var openedBook: Book?
    @State private var confirmDelete: Book?
    @State private var alertMessage: String?
    @State private var isImporting = false

    // iPad：筛选项常驻在左侧栏；批量选择也在这里
    @State private var sidebar: SidebarItem = .all
    @State private var selectMode = false
    @State private var selected: Set<UUID> = []
    @State private var isDropTargeted = false
    @State private var confirmBulkDelete = false
    @State private var showCollections = false
    @State private var showBackup = false

    /// iPad 横屏下一行多放几本，别把大屏浪费掉
    private var columns: [GridItem] {
        let minimum: CGFloat = sizeClass == .regular ? 132 : 108
        return [GridItem(.adaptive(minimum: minimum), spacing: sizeClass == .regular ? 20 : 16)]
    }

    private var allBooks: [Book] { library.sortedBooks(keyword: searchText) }

    private var books: [Book] {
        switch sidebar {
        case .filter(let item): return allBooks.filter { item.matches($0) }
        case .collection(let id): return allBooks.filter { $0.collectionIds.contains(id) }
        }
    }

    private var currentTitle: String {
        switch sidebar {
        case .filter(let item): return item.title
        case .collection(let id): return collections.displayName(of: id)
        }
    }

    private var counts: [LibraryFilter: Int] {
        var result: [LibraryFilter: Int] = [:]
        for item in LibraryFilter.allCases {
            result[item] = allBooks.filter { item.matches($0) }.count
        }
        return result
    }

    private var sizeText: String {
        let total = allBooks.reduce(Int64(0)) { $0 + $1.fileSize }
        guard total > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(
                selection: $sidebar,
                collections: collections,
                counts: counts,
                totalCount: allBooks.count,
                totalSizeDescription: sizeText,
                bookCountIn: { library.books(inCollection: $0).count },
                onManageCollections: { showCollections = true }
            )
        } detail: {
            detail
        }
        .sheet(isPresented: $showCollections) {
            CollectionsView()
                .environmentObject(collections)
                .environmentObject(library)
        }
        .sheet(isPresented: $showBackup) {
            BackupView()
                .environmentObject(library)
                .environmentObject(annotations)
                .environmentObject(collections)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: Self.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importURLs(urls)
            case .failure(let error):
                alertMessage = "导入失败：\(error.localizedDescription)"
            }
        }
        .fullScreenCover(item: $openedBook) { book in
            ReaderContainerView(book: book, library: library, annotations: annotations)
        }
        .confirmationDialog(
            "确定删除这本书？",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            presenting: confirmDelete
        ) { book in
            Button("删除", role: .destructive) {
                delete([book])
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        }
        .confirmationDialog(
            "删除选中的 \(selected.count) 本书？",
            isPresented: $confirmBulkDelete
        ) {
            Button("删除", role: .destructive) {
                let targets = allBooks.filter { selected.contains($0.id) }
                delete(targets)
                selected.removeAll()
                selectMode = false
            }
            Button("取消", role: .cancel) { }
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

    // MARK: - 主区域

    private var detail: some View {
        Group {
            if books.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: sizeClass == .regular ? 24 : 18) {
                        ForEach(books) { book in
                            BookCardView(
                                book: book,
                                isSelecting: selectMode,
                                isSelected: selected.contains(book.id)
                            ) {
                                if selectMode {
                                    toggleSelect(book.id)
                                } else {
                                    openedBook = book
                                }
                            }
                            .contextMenu {
                                Button {
                                    var copy = book
                                    copy.isFavorite.toggle()
                                    library.update(copy)
                                } label: {
                                    Label(book.isFavorite ? "取消收藏" : "收藏",
                                          systemImage: book.isFavorite ? "heart.slash" : "heart")
                                }
                                Button {
                                    selectMode = true
                                    selected = [book.id]
                                } label: {
                                    Label("选择", systemImage: "checkmark.circle")
                                }
                                // 封面：缩略图 / 纯色 / 自定义图片，颜色和收藏夹共用一套 12 色
                                Menu("封面") {
                                    Button {
                                        library.setCover(mode: .thumb, colorHex: nil, for: book.id)
                                    } label: {
                                        Label("内容缩略图", systemImage: "doc.text.image")
                                    }
                                    Button {
                                        library.setCover(
                                            mode: .color,
                                            colorHex: book.coverColorHex ?? BookCollection.palette[0],
                                            for: book.id
                                        )
                                    } label: {
                                        Label("纯色封面", systemImage: "square.fill")
                                    }
                                    Menu("选颜色") {
                                        ForEach(BookCollection.palette, id: \.self) { hex in
                                            Button {
                                                library.setCover(mode: .color, colorHex: hex, for: book.id)
                                            } label: {
                                                HStack {
                                                    Image(systemName: "square.fill")
                                                        .foregroundStyle(Color(hex: hex))
                                                    Text(hex)
                                                }
                                            }
                                        }
                                    }
                                }
                                Button(role: .destructive) {
                                    confirmDelete = book
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(sizeClass == .regular ? 22 : 16)
                }
            }
        }
        .navigationTitle(currentTitle)
        .searchable(text: $searchText, prompt: "搜索书名 / 作者")
        // iPad 上可以直接把「文件」App 里的书拖进来
        .onDrop(of: [.fileURL, .url], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(.ultraThinMaterial.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                    .padding(8)
                    .overlay(alignment: .center) {
                        Text("松手即可导入")
                            .font(.headline)
                            .padding(12)
                            .background(.regularMaterial, in: Capsule())
                    }
            }
        }
        .overlay(alignment: .center) {
            if isImporting { importingOverlay }
        }
        .safeAreaInset(edge: .bottom) {
            if selectMode { bulkBar }
        }
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showImporter = true
            } label: {
                Label("导入", systemImage: "plus")
            }
            .keyboardShortcut("o", modifiers: .command)   // iPad 接键盘：⌘O
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Picker("排序", selection: $library.sortOption) {
                    ForEach(LibraryStore.SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Button {
                    let newBooks = BookImporter.importInboxFiles()
                    for book in newBooks { library.add(book) }
                    alertMessage = newBooks.isEmpty ? "没有发现新文件" : "已导入 \(newBooks.count) 本"
                } label: {
                    Label("扫描「文件」App 导入的书", systemImage: "folder.badge.plus")
                }
                Divider()
                Button {
                    showCollections = true
                } label: {
                    Label("管理收藏夹", systemImage: "folder.badge.gearshape")
                }
                Button {
                    showBackup = true
                } label: {
                    Label("备份与恢复", systemImage: "externaldrive.badge.timemachine")
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                selectMode.toggle()
                if !selectMode { selected.removeAll() }
            } label: {
                Label(selectMode ? "完成" : "选择",
                      systemImage: selectMode ? "checkmark.circle.fill" : "checkmark.circle")
            }
        }
    }

    // MARK: - 批量操作条

    private var bulkBar: some View {
        HStack(spacing: 14) {
            Button("全选") { selected = Set(books.map { $0.id }) }
            Button("反选") {
                let visible = Set(books.map { $0.id })
                selected = visible.subtracting(selected)
            }
            Button("全不选") { selected.removeAll() }
            Spacer()
            Text("已选 \(selected.count) 本")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                let targets = allBooks.filter { selected.contains($0.id) }
                for book in targets {
                    var copy = book
                    copy.isFavorite = true
                    library.update(copy)
                }
                alertMessage = "已收藏 \(targets.count) 本"
            } label: {
                Image(systemName: "heart")
            }
            .disabled(selected.isEmpty)

            Menu {
                if collections.collections.isEmpty {
                    Text("还没有收藏夹")
                } else {
                    ForEach(collections.topLevel) { item in
                        Button(item.name) { addSelected(to: item.id) }
                        ForEach(collections.children(of: item.id)) { kid in
                            Button("　\(kid.name)") { addSelected(to: kid.id) }
                        }
                    }
                    Divider()
                    Button("新建收藏夹并加入") {
                        let item = collections.create(name: "新建收藏夹")
                        addSelected(to: item.id)
                        showCollections = true
                    }
                }
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .disabled(selected.isEmpty)

            if case .collection(let id) = sidebar {
                Button {
                    let targets = allBooks.filter { selected.contains($0.id) }
                    library.remove(Set(targets.map { $0.id }), fromCollection: id)
                    selected.removeAll()
                } label: {
                    Image(systemName: "folder.badge.minus")
                }
                .disabled(selected.isEmpty)
            }
            Button(role: .destructive) {
                confirmBulkDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selected.isEmpty)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - 操作

    private func addSelected(to collectionId: UUID) {
        let ids = Set(allBooks.filter { selected.contains($0.id) }.map { $0.id })
        guard !ids.isEmpty else { return }
        library.add(ids, toCollection: collectionId)
        alertMessage = "已把 \(ids.count) 本加入「\(collections.displayName(of: collectionId))」"
    }

    private func toggleSelect(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func delete(_ targets: [Book]) {
        for book in targets {
            annotations.notes.removeAll { $0.bookId == book.id }
            annotations.bookmarks.removeAll { $0.bookId == book.id }
            annotations.highlights.removeAll { $0.bookId == book.id }
            annotations.save()
            library.delete(book)
        }
    }

    private func importURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        let captured = urls
        Task.detached(priority: .userInitiated) {
            let newBooks = BookImporter.importBooks(from: captured)
            await MainActor.run {
                for book in newBooks { library.add(book) }
                isImporting = false
                alertMessage = newBooks.isEmpty
                    ? "没有可导入的文件（支持 txt / pdf / epub / cbz / zip / 图片）"
                    : "已导入 \(newBooks.count) 本"
            }
        }
    }

    /// 拖放导入：iPad 上从「文件」App 拖书进来
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in self.importURLs([url]) }
            }
        }
        return accepted
    }

    // MARK: - 子视图

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("导入中…").font(.subheadline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private static var supportedTypes: [UTType] {
        var types: [UTType] = [.data, .pdf, .plainText, .image, .zip]
        if let epub = UTType(filenameExtension: "epub") { types.append(epub) }
        if let cbz = UTType(filenameExtension: "cbz") { types.append(cbz) }
        if let txt = UTType(filenameExtension: "txt") { types.append(txt) }
        return types
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.headline)
            Text(emptySubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showImporter = true
            } label: {
                Label("导入书籍", systemImage: "plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 空状态也得分清「书库空」和「筛没了」，否则搜不到书时只剩一片空白
    private var emptyTitle: String {
        allBooks.isEmpty ? "书架还是空的" : "这里没有书"
    }

    private var emptySubtitle: String {
        if allBooks.isEmpty {
            return "支持 TXT / PDF / EPUB / CBZ、ZIP 漫画包，也可以一次选中多张图片打包成一本"
        }
        if !searchText.isEmpty {
            return "「\(searchText)」在「\(currentTitle)」里没有结果"
        }
        if case .collection = sidebar {
            return "这个收藏夹还是空的。在书上加长按/右键，或者在批量选择里「加入收藏夹」"
        }
        return "「\(currentTitle)」里还没有书，换一个分类看看"
    }
}

// MARK: - 书卡片

struct BookCardView: View {
    let book: Book
    var isSelecting: Bool = false
    var isSelected: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    cover
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

                    if book.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(6)
                    }

                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.white)
                            .padding(6)
                            .background(Color.black.opacity(0.25), in: Circle())
                            .padding(4)
                    }
                }

                Text(book.title)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                ProgressView(value: book.progress)
                    .tint(.accentColor)
                    .scaleEffect(x: 1, y: 0.6, anchor: .center)

                HStack(spacing: 4) {
                    Image(systemName: book.format.symbolName)
                    Text(book.progress > 0 ? "\(Int(book.progress * 100))%" : "未读")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// 封面三选：缩略图（默认）/ 纯色 / 自定义图片
    ///
    /// 注意 `image` 和 `thumb` 走的是同一份 coverFileName —— 区别只在语义上：
    /// thumb 是导入时自动生成的，image 是用户后换的，都不需要额外存文件。
    @ViewBuilder
    private var cover: some View {
        if book.coverMode == .color {
            ZStack {
                Color(hex: book.coverColorHex ?? BookCollection.palette[0])
                Text(book.title.prefix(6))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(6)
            }
        } else if let url = book.coverURL,
                  let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "#5A6C8A"), Color(hex: "#2F3B4C")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(book.title.prefix(6))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(6)
            }
        }
    }
}
