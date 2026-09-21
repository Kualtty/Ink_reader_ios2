import SwiftUI

/// 收藏夹管理：新建 / 重命名 / 12 色配色 / 排序 / 嵌套 / 清空 / 删除
struct CollectionsView: View {
    @EnvironmentObject private var collections: CollectionStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var showNew = false
    @State private var newName = ""
    @State private var newParent: UUID?

    @State private var renameTarget: BookCollection?
    @State private var renameText = ""

    @State private var colorTarget: BookCollection?
    @State private var deleteTarget: BookCollection?
    @State private var clearTarget: BookCollection?

    var body: some View {
        NavigationStack {
            Group {
                if collections.collections.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(flattened, id: \.collection.id) { item in
                            row(item)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleteTarget = item.collection
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    Button {
                                        beginRename(item.collection)
                                    } label: {
                                        Label("重命名", systemImage: "pencil")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("收藏夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        newParent = nil
                        newName = ""
                        showNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("新建收藏夹", isPresented: $showNew) {
                TextField("名称", text: $newName)
                Button("创建") {
                    let name = newName.trimmed
                    guard !name.isEmpty else { return }
                    _ = collections.create(name: name, parentId: newParent)
                    newName = ""
                }
                Button("取消", role: .cancel) { }
            }
            .alert("重命名", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("名称", text: $renameText)
                Button("保存") {
                    if let target = renameTarget, !renameText.trimmed.isEmpty {
                        collections.rename(target.id, to: renameText)
                    }
                    renameTarget = nil
                }
                Button("取消", role: .cancel) { renameTarget = nil }
            }
            .sheet(item: $colorTarget) { target in
                ColorPickerSheet(
                    title: target.name,
                    selected: target.colorHex
                ) { hex in
                    collections.setColor(target.id, hex: hex)
                    colorTarget = nil
                }
            }
            .confirmationDialog(
                "删除收藏夹？",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                presenting: deleteTarget
            ) { target in
                Button("只删收藏夹，书保留", role: .destructive) {
                    let removed = collections.delete(target.id)
                    library.pruneCollectionReferences(removed)
                    deleteTarget = nil
                }
                Button("取消", role: .cancel) { deleteTarget = nil }
            } message: { target in
                Text("「\(target.name)」里的 \(library.books(inCollection: target.id).count) 本书不会被删除，只是从这个收藏夹里移出。")
            }
            .confirmationDialog(
                "清空收藏夹？",
                isPresented: Binding(
                    get: { clearTarget != nil },
                    set: { if !$0 { clearTarget = nil } }
                ),
                presenting: clearTarget
            ) { target in
                Button("移出全部书", role: .destructive) {
                    let ids = collections.clear(target.id)
                    let bookIds = Set(library.books(inCollection: target.id).map { $0.id })
                    for id in ids { library.remove(bookIds, fromCollection: id) }
                    clearTarget = nil
                }
                Button("取消", role: .cancel) { clearTarget = nil }
            } message: { target in
                Text("收藏夹「\(target.name)」会保留，里面的书被移出。")
            }
        }
    }

    // MARK: - 行

    private func row(_ item: (collection: BookCollection, depth: Int)) -> some View {
        let count = library.books(inCollection: item.collection.id).count
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: item.collection.colorHex))
                .frame(width: 6, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.collection.name)
                    .font(.body)
                Text("\(count) 本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Menu {
                Button {
                    beginRename(item.collection)
                } label: {
                    Label("重命名", systemImage: "pencil")
                }
                Button {
                    colorTarget = item.collection
                } label: {
                    Label("换颜色", systemImage: "paintpalette")
                }
                Button {
                    collections.shift(item.collection.id, by: -1)
                } label: {
                    Label("上移", systemImage: "arrow.up")
                }
                Button {
                    collections.shift(item.collection.id, by: 1)
                } label: {
                    Label("下移", systemImage: "arrow.down")
                }
                Menu("移动到…") {
                    Button("顶层") { collections.move(item.collection.id, toParent: nil) }
                    ForEach(moveCandidates(for: item.collection), id: \.id) { candidate in
                        Button(candidate.name) {
                            collections.move(item.collection.id, toParent: candidate.id)
                        }
                    }
                }
                Button {
                    newParent = item.collection.id
                    newName = ""
                    showNew = true
                } label: {
                    Label("在下面建子夹", systemImage: "folder.badge.plus")
                }
                Button {
                    clearTarget = item.collection
                } label: {
                    Label("清空里面的书", systemImage: "square.dashed")
                }
                Button(role: .destructive) {
                    deleteTarget = item.collection
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, CGFloat(item.depth) * 16)
        .contentShape(Rectangle())
    }

    private func moveCandidates(for item: BookCollection) -> [BookCollection] {
        let banned = Set(collections.collections.descendants(of: item.id))
        return collections.collections
            .filter { !banned.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func beginRename(_ item: BookCollection) {
        renameText = item.name
        renameTarget = item
    }

    // MARK: - 子视图

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("还没有收藏夹")
                .font(.headline)
            Text("可以把漫画、小说、资料分别归到不同的收藏夹里，还支持子夹和 12 种配色。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                newParent = nil
                newName = ""
                showNew = true
            } label: {
                Label("新建收藏夹", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

// MARK: - 配色选择

private struct ColorPickerSheet: View {
    let title: String
    let selected: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(BookCollection.palette, id: \.self) { hex in
                        Button {
                            onPick(hex)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(hex: hex))
                                    .frame(height: 56)
                                if hex.caseInsensitiveCompare(selected) == .orderedSame {
                                    Image(systemName: "checkmark")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
