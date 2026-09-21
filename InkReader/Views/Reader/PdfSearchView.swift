import PDFKit
import SwiftUI

// MARK: - 命中项

struct PdfSearchHit: Identifiable {
    let id = UUID()
    /// 页码索引（0 开始）
    let pageIndex: Int
    let snippet: String
    let selection: PDFSelection

    var pageLabel: String { "第 \(pageIndex + 1) 页" }
}

// MARK: - 检索器

/// PDF 全文检索。用 PDFDocument.findString 拿 PDFSelection，
/// 点结果时既能跳页，也能把那一处高亮出来（比单纯跳页好用得多）。
@MainActor
final class PdfSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var hits: [PdfSearchHit] = []
    @Published var isSearching = false
    @Published var hasSearched = false
    @Published var errorMessage: String?

    private let document: PDFDocument?
    private var runningTask: Task<Void, Never>?

    init(document: PDFDocument?) {
        self.document = document
    }

    func clear() {
        query = ""
        hits = []
        hasSearched = false
        errorMessage = nil
    }

    func run() {
        let keyword = query.trimmed
        runningTask?.cancel()
        guard keyword.count >= 1 else {
            hits = []
            hasSearched = false
            return
        }
        guard let document else {
            errorMessage = "这份 PDF 还没打开完"
            return
        }

        isSearching = true
        errorMessage = nil
        runningTask = Task.detached(priority: .userInitiated) { [weak self] in
            let selections = document.findString(keyword, withOptions: [.caseInsensitive, .diacriticInsensitive])
            var results: [PdfSearchHit] = []
            for selection in selections {
                guard let page = selection.pages.first else { continue }
                let index = document.index(for: page)
                guard index != NSNotFound else { continue }
                let text = Self.snippet(around: selection, on: page)
                results.append(PdfSearchHit(pageIndex: index, snippet: text, selection: selection))
            }
            // findString 的顺序不完全等于页码顺序，按页码排一遍更符合直觉
            results.sort { $0.pageIndex == $1.pageIndex ? $0.id.uuidString < $1.id.uuidString : $0.pageIndex < $1.pageIndex }

            let capped = Array(results.prefix(1000))
            await MainActor.run {
                guard let self else { return }
                self.hits = capped
                self.isSearching = false
                self.hasSearched = true
            }
        }
    }

    /// 命中前后各带一点上下文，只有一个词的时候看不出在哪
    private static func snippet(around selection: PDFSelection, on page: PDFPage) -> String {
        let hit = (selection.string ?? "").replacingOccurrences(of: "\n", with: " ")
        guard !hit.isEmpty else { return "" }
        guard let pageText = page.string, !pageText.isEmpty else { return hit }

        let ns = pageText as NSString
        let range = ns.range(of: hit, options: .caseInsensitive)
        guard range.location != NSNotFound else { return hit }

        let lead = 24
        let tail = 40
        let start = max(0, range.location - lead)
        let end = min(ns.length, NSMaxRange(range) + tail)
        let raw = ns.substring(with: NSRange(location: start, length: max(0, end - start)))
            .replacingOccurrences(of: "\n", with: " ")
        return (start > 0 ? "…" : "") + raw + (end < ns.length ? "…" : "")
    }
}

// MARK: - 搜索面板

struct PdfSearchView: View {
    @ObservedObject var vm: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var searcher: PdfSearchViewModel
    @State private var cursor: Int = 0

    /// ReaderViewModel 是 @MainActor 的，这里同步一下，
    /// 免得在 Swift 6 语言模式下报「从非隔离上下文访问主线程属性」
    @MainActor
    init(vm: ReaderViewModel) {
        self.vm = vm
        self._searcher = StateObject(
            wrappedValue: PdfSearchViewModel(document: vm.pdfDocument)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                if !searcher.hits.isEmpty { hitNavigator }
            }
            .searchable(text: $searcher.query, prompt: "搜索 PDF 正文")
            .onSubmit(of: .search) { searcher.run() }
            .onChange(of: searcher.query) { _ in
                // 中文一个字就能搜，但一个字结果太多；两个字起实时搜，一个字等回车
                if searcher.query.trimmed.count >= 2 { searcher.run() }
            }
            .navigationTitle("搜索 PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if searcher.isSearching {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = searcher.errorMessage {
            // 用字面量做标题 + Text 做描述，避免 String 变量转 LocalizedStringKey 的歧义
            ContentUnavailableView(
                "搜索失败",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        } else if searcher.hits.isEmpty {
            ContentUnavailableView(
                searcher.hasSearched ? "没有找到结果" : "输入关键词搜索",
                systemImage: "magnifyingglass"
            )
        } else {
            List(Array(searcher.hits.enumerated()), id: \.element.id) { pair in
                // 不写成 { index, hit in } —— 元组解包在不同 Swift 版本下不一致
                let index = pair.offset
                let hit = pair.element
                Button {
                    goto(index, andDismiss: true)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.snippet)
                                .font(.callout)
                                .lineLimit(3)
                            Text(hit.pageLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if index == cursor {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    /// 底部「上一个 / 下一个」：像 Web 原型那样显示 2 / 7 · 第 41 页
    private var hitNavigator: some View {
        HStack(spacing: 16) {
            Button {
                goto(cursor - 1, andDismiss: false)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(cursor <= 0)

            Text(positionText)
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)

            Button {
                goto(cursor + 1, andDismiss: false)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(cursor >= searcher.hits.count - 1)

            Spacer()

            Button("跳过去") {
                goto(cursor, andDismiss: true)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var positionText: String {
        guard searcher.hits.indices.contains(cursor) else { return "0 / \(searcher.hits.count)" }
        let hit = searcher.hits[cursor]
        return "\(cursor + 1) / \(searcher.hits.count) · 第 \(hit.pageIndex + 1) 页"
    }

    private func goto(_ index: Int, andDismiss: Bool) {
        guard searcher.hits.indices.contains(index) else { return }
        cursor = index
        let hit = searcher.hits[index]
        vm.goToPage(hit.pageIndex)
        vm.setPdfHighlight(hit.selection)
        if andDismiss { dismiss() }
    }
}
