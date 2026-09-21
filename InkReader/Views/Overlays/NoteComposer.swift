import SwiftUI

// MARK: - 笔记编辑

struct NoteComposer: View {
    @ObservedObject var vm: ReaderViewModel
    var page: Int
    var locator: String
    var quote: String = ""
    var range: NSRange?
    var editing: Note?

    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""
    @State private var colorHex: String = "#FFD54F"
    @State private var alsoHighlight: Bool = true

    private let palette = ["#FFD54F", "#81C784", "#64B5F6", "#F06292", "#FF8A65", "#BA68C8"]

    var body: some View {
        NavigationStack {
            Form {
                if !quote.isEmpty {
                    Section("原文") {
                        Text(quote)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("笔记内容") {
                    TextEditor(text: $content)
                        .frame(minHeight: 140)
                }

                if range != nil {
                    Section {
                        Toggle("同时高亮原文", isOn: $alsoHighlight)
                    }
                }

                Section("标记颜色") {
                    HStack(spacing: 14) {
                        ForEach(palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: colorHex == hex ? 2.5 : 0)
                                        .padding(-4)
                                )
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(editing == nil ? "新建笔记" : "编辑笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(content.trimmed.isEmpty && editing == nil)
                }
            }
            .onAppear {
                if let editing {
                    content = editing.content
                    colorHex = editing.colorHex
                }
            }
        }
    }

    private func save() {
        if var note = editing {
            note.content = content
            note.colorHex = colorHex
            note.updatedAt = Date()
            vm.annotations.update(note)
            for highlight in vm.annotations.highlights(for: vm.book.id) where highlight.noteId == note.id {
                var copy = highlight
                copy.colorHex = colorHex
                vm.annotations.deleteHighlight(highlight)
                vm.annotations.addHighlight(copy)
            }
        } else {
            let note = Note(
                bookId: vm.book.id,
                kind: quote.isEmpty ? .memo : .highlight,
                page: page,
                locator: locator,
                quote: quote,
                content: content,
                colorHex: colorHex
            )
            vm.annotations.add(note)
            if let range, alsoHighlight {
                vm.annotations.removeHighlights(bookId: vm.book.id, overlapping: range)
                vm.annotations.addHighlight(
                    HighlightRange(
                        bookId: vm.book.id,
                        start: range.location,
                        length: range.length,
                        colorHex: colorHex,
                        noteId: note.id
                    )
                )
            }
        }
        dismiss()
    }
}

// MARK: - 书签 / 笔记列表

struct NoteBookmarkListView: View {
    @ObservedObject var vm: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var segment = 0
    @State private var editingNote: Note?

    private var bookmarks: [Bookmark] { vm.annotations.bookmarks(for: vm.book.id) }
    private var notes: [Note] { vm.annotations.notes(for: vm.book.id) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $segment) {
                    Text("书签 \(bookmarks.count)").tag(0)
                    Text("笔记 \(notes.count)").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                List {
                    if segment == 0 {
                        if bookmarks.isEmpty { placeholder("还没有书签") }
                        ForEach(bookmarks) { bookmark in
                            Button {
                                vm.goToLocator(bookmark.locator)
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "bookmark.fill")
                                        .foregroundColor(.orange)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("第 \(bookmark.page + 1) 页")
                                            .font(.subheadline.weight(.semibold))
                                        if !bookmark.excerpt.isEmpty {
                                            Text(bookmark.excerpt)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                vm.annotations.removeBookmark(bookmarks[index])
                            }
                        }
                    } else {
                        if notes.isEmpty { placeholder("还没有笔记") }
                        ForEach(notes) { note in
                            Button {
                                vm.goToLocator(note.locator)
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(Color(hex: note.colorHex))
                                        .frame(width: 10, height: 10)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("第 \(note.page + 1) 页")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if !note.quote.isEmpty {
                                            Text("「\(note.quote)」")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Text(note.content)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    vm.annotations.delete(note)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    editingNote = note
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle(vm.book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $editingNote) { note in
                NoteComposer(
                    vm: vm,
                    page: note.page,
                    locator: note.locator,
                    quote: note.quote,
                    range: nil,
                    editing: note
                )
            }
        }
    }

    @ViewBuilder
    private func placeholder(_ text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 40)
            Spacer()
        }
        .listRowSeparator(.hidden)
    }
}
