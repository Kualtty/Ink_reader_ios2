import SwiftUI
import UniformTypeIdentifiers

// MARK: - 备份文件（就是一个 zip，导出时给个好认的名字）

struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - 备份与恢复

struct BackupView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var annotations: AnnotationStore
    @EnvironmentObject private var collections: CollectionStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: BackupMode = .merge
    @State private var isWorking = false
    @State private var workingText = ""
    @State private var progress: Double = 0

    @State private var exportDoc: BackupFile?
    @State private var defaultFilename = "InkReader-备份.zip"

    @State private var showImporter = false
    @State private var pendingImport: URL?
    @State private var confirmImport = false

    @State private var showPicker = false
    @State private var picked: Set<UUID> = []

    @State private var alertTitle = ""
    @State private var alertMessage: String?

    private var annotationCount: Int {
        annotations.bookmarks.count + annotations.notes.count + annotations.highlights.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label("当前书架", systemImage: "books.vertical")
                        Spacer()
                        Text("\(library.books.count) 本")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("笔记 / 书签 / 高亮", systemImage: "note.text")
                        Spacer()
                        Text("\(annotationCount) 条")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("收藏夹", systemImage: "folder")
                        Spacer()
                        Text("\(collections.collections.count) 个")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("现在")
                }

                Section {
                    Button {
                        prepareExport(only: nil)
                    } label: {
                        Label("备份整库", systemImage: "square.and.arrow.up")
                    }
                    .disabled(library.books.isEmpty)

                    Button {
                        picked = []
                        showPicker = true
                    } label: {
                        Label("只备份选中的书", systemImage: "checklist")
                    }
                    .disabled(library.books.isEmpty)
                } header: {
                    Text("导出")
                } footer: {
                    Text("导出的是一个 zip 包，包含书的文件、封面、阅读进度、笔记书签、手写涂鸦和收藏夹。可以存到「文件」App 或隔空投送到另一台设备。")
                }

                Section {
                    Picker("恢复方式", selection: $mode) {
                        ForEach(BackupMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(mode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        showImporter = true
                    } label: {
                        Label("选择备份文件", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("导入")
                } footer: {
                    Text("覆盖模式会先清掉现有的书和笔记，请确认已经导出过当前数据。")
                }
            }
            .navigationTitle("备份与恢复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .overlay {
                if isWorking { workingOverlay }
            }
            .fileExporter(
                isPresented: Binding(
                    get: { exportDoc != nil },
                    set: { if !$0 { exportDoc = nil } }
                ),
                document: exportDoc,
                contentType: .zip,
                defaultFilename: defaultFilename
            ) { result in
                exportDoc = nil
                if case .failure(let error) = result {
                    alertTitle = "导出失败"
                    alertMessage = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.zip, .data]
            ) { result in
                switch result {
                case .success(let url):
                    pendingImport = url
                    confirmImport = true
                case .failure(let error):
                    alertTitle = "读取失败"
                    alertMessage = error.localizedDescription
                }
            }
            .confirmationDialog(
                "用备份\(mode.title)现在的数据？",
                isPresented: $confirmImport
            ) {
                Button(mode == .overwrite ? "覆盖恢复" : "合并恢复") {
                    if let url = pendingImport { restore(url) }
                    pendingImport = nil
                }
                Button("取消", role: .cancel) { pendingImport = nil }
            } message: {
                Text(mode == .overwrite ? "现有的书架和笔记会被替换掉。" : "只补进备份里有、现在没有的书。")
            }
            .sheet(isPresented: $showPicker) {
                BookPickerSheet(all: library.books, selected: $picked) { ids in
                    showPicker = false
                    prepareExport(only: ids)
                }
            }
            .alert(alertTitle, isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好") { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    // MARK: - 动作

    private func prepareExport(only: Set<UUID>?) {
        guard !library.books.isEmpty else { return }
        let scoped = only.flatMap { Set(library.books.map(\.id)).intersection($0) }
        let ids = scoped?.isEmpty == true ? nil : scoped

        isWorking = true
        workingText = "打包中…"
        let stamp = Self.dateStamp()
        let fileName = "InkReader-\(stamp).zip"
        let target = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)

        let lib = library
        let col = collections
        let ann = annotations

        Task.detached(priority: .userInitiated) {
            do {
                let summary = try BackupService.exportBackup(
                    only: ids,
                    library: lib,
                    collections: col,
                    annotations: ann,
                    toZip: target
                )
                let data = (try? Data(contentsOf: target)) ?? Data()
                try? FileManager.default.removeItem(at: target)
                await MainActor.run {
                    isWorking = false
                    guard !data.isEmpty else {
                        alertTitle = "导出失败"
                        alertMessage = "打包出来的文件是空的"
                        return
                    }
                    defaultFilename = fileName
                    exportDoc = BackupFile(data: data)
                }
                _ = summary
            } catch {
                await MainActor.run {
                    isWorking = false
                    alertTitle = "导出失败"
                    alertMessage = error.localizedDescription
                }
            }
        }
    }

    private func restore(_ url: URL) {
        isWorking = true
        workingText = "恢复中…"
        let lib = library
        let col = collections
        let ann = annotations
        let chosen = mode

        Task.detached(priority: .userInitiated) {
            do {
                // 安全域：fileImporter 给的 URL 需要先取得访问权
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }

                let summary = try BackupService.restoreBackup(
                    fromZip: url,
                    mode: chosen,
                    library: lib,
                    collections: col,
                    annotations: ann
                )
                await MainActor.run {
                    isWorking = false
                    alertTitle = "恢复完成"
                    alertMessage = "共导入 \(summary.books) 本书、\(summary.annotations) 条笔记/书签/高亮"
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    alertTitle = "恢复失败"
                    alertMessage = error.localizedDescription
                }
            }
        }
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: Date())
    }

    private var workingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(workingText).font(.subheadline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - 选书

private struct BookPickerSheet: View {
    let all: [Book]
    @Binding var selected: Set<UUID>
    let onConfirm: (Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(all) { book in
                Button {
                    if selected.contains(book.id) { selected.remove(book.id) }
                    else { selected.insert(book.id) }
                } label: {
                    HStack {
                        Image(systemName: book.format.symbolName)
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        Text(book.title).lineLimit(1)
                        Spacer()
                        if selected.contains(book.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("选择要备份的书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("备份这 \(selected.count) 本") { onConfirm(selected) }
                        .disabled(selected.isEmpty)
                }
            }
        }
    }
}
