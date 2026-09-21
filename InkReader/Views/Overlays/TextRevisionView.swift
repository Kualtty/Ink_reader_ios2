//  墨阅 InkReader · InkReader/Views/Overlays/TextRevisionView.swift
//  功能：修订界面 —— 编辑原文弹窗（显示字数增减）、修订记录列表、撤销上一次、失效标注重新定位。
//  要点：只在 TXT / EPUB 暴露入口。

import SwiftUI

// MARK: - 编辑原文

/// 划词后点「编辑原文」传进来的请求
struct RevisionRequest: Identifiable {
    let id = UUID()
    let range: NSRange
    let text: String
}

struct TextRevisionEditor: View {
    @ObservedObject var vm: ReaderViewModel
    let request: RevisionRequest
    @Environment(\.dismiss) private var dismiss

    @State private var draft: String

    init(vm: ReaderViewModel, request: RevisionRequest) {
        self.vm = vm
        self.request = request
        self._draft = State(initialValue: request.text)
    }

    private var delta: Int { (draft as NSString).length - request.range.length }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("改的是原文文件本身，不只是显示。改完会自动平移后面的高亮、书签和笔记；"
                     + "和改动区间部分重叠的标注会标成「失效」，可以在「修订记录」里重新定位。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 240)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.25))
                    )

                HStack {
                    Text("原文 \(request.range.length) 字")
                    Image(systemName: "arrow.right")
                    Text("现在 \((draft as NSString).length) 字")
                    if delta != 0 {
                        Text(delta > 0 ? "（+\(delta)）" : "（\(delta)）")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("编辑原文")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        vm.applyRevision(range: request.range, replacement: draft)
                        dismiss()
                    }
                    .disabled(draft == request.text)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 修订记录

struct RevisionHistoryView: View {
    @ObservedObject var vm: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    private var records: [TextRevision] {
        vm.revisions.revisions(for: vm.book.id).reversed()
    }

    private var orphans: [OrphanAnnotation] {
        vm.revisions.orphans(for: vm.book.id)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        vm.undoLastRevision()
                    } label: {
                        Label("撤销上一次修订", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(records.isEmpty)
                    Text("最多可撤销 \(records.count) 步（按最近一次往前退）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !orphans.isEmpty {
                    Section("⚠ 失效标注 \(orphans.count)") {
                        ForEach(orphans) { orphan in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(orphan.kindTitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(orphan.quote.isEmpty ? "（无原文片段）" : orphan.quote)
                                        .font(.footnote)
                                        .lineLimit(3)
                                }
                                Spacer()
                                Button("重新定位") {
                                    vm.relocate(orphan)
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet { vm.dropOrphan(orphans[index]) }
                        }
                    }
                }

                Section("修订记录 \(records.count)") {
                    if records.isEmpty {
                        Text("还没改过原文")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(records) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.timeText(item.createdAt) + " · 偏移 \(item.location)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("「\(item.oldText.prefix(24))」→「\(item.newText.prefix(24))」")
                                    .font(.footnote)
                            }
                        }
                    }
                }
            }
            .navigationTitle("原文修订")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private static func timeText(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }
}
