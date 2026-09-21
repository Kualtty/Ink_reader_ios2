import SwiftUI

// MARK: - 目录

struct ChapterListView: View {
    @ObservedObject var vm: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Chapter] {
        guard !query.trimmed.isEmpty else { return vm.chapters }
        let kw = query.trimmed.lowercased()
        return vm.chapters.filter { $0.title.lowercased().contains(kw) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { chapter in
                Button {
                    vm.jumpToOffset(chapter.offset)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(chapter.title)
                            .lineLimit(2)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "搜索章节")
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 全文搜索

/// 入口：按书的类型分流。PDF 走 PDFKit 的检索，文本书走字符串检索。
struct ReaderSearchView: View {
    @ObservedObject var vm: ReaderViewModel

    var body: some View {
        Group {
            if vm.book.format == .pdf {
                PdfSearchView(vm: vm)
            } else {
                TextSearchView(vm: vm)
            }
        }
    }
}

/// 文本书（TXT / EPUB）的全文搜索
struct TextSearchView: View {
    @ObservedObject var vm: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [(offset: Int, snippet: String)] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    if isSearching {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            query.isEmpty ? "输入关键词搜索" : "没有找到结果",
                            systemImage: "magnifyingglass"
                        )
                    }
                } else {
                    List(results, id: \.offset) { item in
                        Button {
                            vm.jumpToOffset(item.offset)
                            dismiss()
                        } label: {
                            Text(item.snippet)
                                .font(.callout)
                                .lineLimit(3)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "搜索正文")
            .onSubmit(of: .search) { runSearch() }
            .onChange(of: query) { _ in
                if query.count >= 2 { runSearch() }
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func runSearch() {
        let keyword = query.trimmed
        guard keyword.count >= 1 else { results = []; return }
        isSearching = true
        let text = vm.plainText
        Task.detached(priority: .userInitiated) {
            let ns = text as NSString
            var found: [(Int, String)] = []
            var searchRange = NSRange(location: 0, length: ns.length)
            while found.count < 500 {
                let hit = ns.range(of: keyword, options: .caseInsensitive, range: searchRange)
                if hit.location == NSNotFound { break }
                let snippetRange = NSRange(
                    location: max(0, hit.location - 20),
                    length: min(80, ns.length - max(0, hit.location - 20))
                )
                found.append((hit.location, ns.substring(with: snippetRange)))
                let next = NSMaxRange(hit)
                if next >= ns.length { break }
                searchRange = NSRange(location: next, length: ns.length - next)
            }
            await MainActor.run {
                self.results = found
                self.isSearching = false
            }
        }
    }
}
