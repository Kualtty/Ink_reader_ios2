//  墨阅 InkReader · InkReader/Views/Reader/ReaderContainerView.swift
//  功能：阅读器容器 —— 顶栏 / 底栏、点击与手势、sheet 路由（目录 / 笔记 / 设置 / 修订 / 查词）、自动翻页计时。
//  要点：ReaderSheet 枚举新增一项时，这里和 ReaderViewModel 都要同步。

import SwiftUI
import UIKit

/// 待创建的划词笔记
private struct PendingNote: Identifiable {
    let id = UUID()
    let range: NSRange
    let quote: String
}

struct ReaderContainerView: View {
    let book: Book
    @ObservedObject var library: LibraryStore
    @ObservedObject var annotations: AnnotationStore
    @ObservedObject var revisions: RevisionStore
    @ObservedObject var pages: ComicPageStore

    @StateObject private var vm: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pendingNote: PendingNote?
    @State private var showNoteComposer = false
    @State private var showCloseConfirm = false
    @State private var showJumpPage = false
    @State private var jumpPageText = ""
    @State private var lookupTerm: LookupTerm?
    @State private var revisionRequest: RevisionRequest?

    init(book: Book,
         library: LibraryStore,
         annotations: AnnotationStore,
         revisions: RevisionStore,
         pages: ComicPageStore) {
        self.book = book
        self._library = ObservedObject(wrappedValue: library)
        self._annotations = ObservedObject(wrappedValue: annotations)
        self._revisions = ObservedObject(wrappedValue: revisions)
        self._pages = ObservedObject(wrappedValue: pages)
        self._vm = StateObject(
            wrappedValue: ReaderViewModel(
                book: book,
                library: library,
                annotations: annotations,
                revisions: revisions,
                pages: pages
            )
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            vm.settings.backgroundColor.ignoresSafeArea()

            contentLayer

            if vm.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(vm.statusText)
                        .font(.subheadline)
                        .foregroundStyle(vm.settings.textColor.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 手写涂鸦层
            if vm.annotationMode {
                AnnotationCanvasView(vm: vm)
                    .zIndex(5)
            } else if annotations.hasDrawing(bookId: vm.book.id, anchor: vm.drawingAnchor) {
                DrawingPreview(drawing: annotations.drawing(for: vm.book.id, anchor: vm.drawingAnchor))
                    .zIndex(4)
                    .allowsHitTesting(false)
            }

            // 工具栏
            if vm.barsVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
                .zIndex(8)
            }

            // 常驻小按钮
            if !vm.barsVisible && !vm.annotationMode {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { vm.barsVisible = true }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.footnote.weight(.semibold))
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(.trailing, 14)
                        .padding(.bottom, 26)
                    }
                }
                .opacity(0.75)
                .zIndex(7)
            }

            // 自动翻页悬浮条（播读时让位给播读条，两个叠一起太吵）
            if vm.autoPlaying && !vm.annotationMode && !vm.speechOn {
                autoPlayBar
                    .zIndex(9)
            }

            // 播读条：暂停/继续 + 调速 + 当前这句
            if vm.speechOn && !vm.annotationMode {
                speechBar
                    .zIndex(9)
            }

            if let toast = vm.toast {
                Text(toast)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 120)
                    .zIndex(10)
                    .transition(.opacity)
            }
        }
        .statusBarHidden(!vm.barsVisible)
        .animation(.easeOut(duration: 0.2), value: vm.barsVisible)
        .task { await vm.load() }
        .onAppear { configureVolumeKeys(vm.settings.volumeKeyTurn) }
        .onDisappear {
            vm.saveNow()
            vm.stopSpeech()
            VolumeKeyObserver.shared.setEnabled(false)
        }
        .onChange(of: vm.settings.volumeKeyTurn) { enabled in
            configureVolumeKeys(enabled)
        }
        .onChange(of: vm.settings.direction) { _ in
            vm.settingsDidChange()
        }
        .onChange(of: vm.toast) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if vm.toast != nil { vm.toast = nil }
            }
        }
        .sheet(item: $vm.sheet) { sheet in
            switch sheet {
            case .settings: SettingsPanel(vm: vm)
            case .notes: NoteBookmarkListView(vm: vm)
            case .chapters: ChapterListView(vm: vm)
            case .search: ReaderSearchView(vm: vm)
            case .jump: ChapterListView(vm: vm)
            case .revisions: RevisionHistoryView(vm: vm)
            }
        }
        .sheet(item: $revisionRequest) { request in
            TextRevisionEditor(vm: vm, request: request)
        }
        .sheet(item: $lookupTerm) { term in
            LookupSheet(term: term.text)
        }
        .sheet(item: $pendingNote) { pending in
            NoteComposer(
                vm: vm,
                page: vm.currentPage,
                locator: vm.currentLocator,
                quote: pending.quote,
                range: pending.range
            )
        }
        .sheet(isPresented: $showNoteComposer) {
            NoteComposer(
                vm: vm,
                page: vm.currentPage,
                locator: vm.currentLocator,
                quote: "",
                range: nil
            )
        }
        .confirmationDialog("退出阅读？", isPresented: $showCloseConfirm) {
            Button("退出并返回书架", role: .destructive) { dismiss() }
            Button("继续阅读", role: .cancel) { }
        }
        // 跳页：底栏页码点一下就能输数字
        .alert("跳到哪一页？", isPresented: $showJumpPage) {
            TextField("页码", text: $jumpPageText)
                .keyboardType(.numberPad)
            Button("跳过去") { commitJumpPage() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("当前 \(vm.currentPage + 1) / \(vm.totalPages) 页")
        }
        // iPad 接了键盘 / 妙控键盘时，方向键直接翻页（工具栏隐藏着也能用）
        .onKeyPress(phases: .down) { press in
            switch press.key {
            case .leftArrow, .upArrow, .pageUp:
                vm.previous()
                return .handled
            case .rightArrow, .downArrow, .pageDown:
                vm.next()
                return .handled
            default:
                return .ignored
            }
        }
    }

    /// 跳页输入的落地：越界要么拦下、要么夹到边界，绝不静默乱跳
    private func commitJumpPage() {
        let digits = jumpPageText.trimmingCharacters(in: .whitespacesAndNewlines)
        jumpPageText = ""
        guard let number = Int(digits), number > 0 else {
            vm.toast = "请输入页码数字"
            return
        }
        if number > vm.totalPages {
            vm.toast = "只有 \(vm.totalPages) 页"
            return
        }
        vm.goToPage(number - 1)
    }

    // MARK: - 内容层

    @ViewBuilder
    private var contentLayer: some View {
        if !vm.isLoading {
            switch vm.book.format {
            case .txt, .epub:
                if vm.settings.direction == .horizontal {
                    TxtPagedReader(vm: vm, onSelect: handleTextAction)
                } else {
                    TxtScrollReaderContainer(vm: vm, onSelect: handleTextAction)
                }
            case .pdf:
                PdfReaderContainer(vm: vm)
            case .comic:
                ComicReaderContainer(vm: vm)
            }
        }
    }

    private func handleTextAction(_ range: NSRange, _ text: String, _ action: TextAction) {
        switch action {
        case .highlight:
            annotations.removeHighlights(bookId: vm.book.id, overlapping: range)
            annotations.addHighlight(
                HighlightRange(
                    bookId: vm.book.id,
                    start: range.location,
                    length: range.length
                )
            )
            vm.toast = "已高亮"
        case .note:
            pendingNote = PendingNote(range: range, quote: text)
        case .lookup:
            lookupTerm = LookupTerm(text: text)
        case .speak:
            vm.speakSelection(text)
        case .revise:
            guard vm.canRevise else {
                vm.toast = "PDF / 漫画是固定版面，改不了原文"
                return
            }
            revisionRequest = RevisionRequest(range: range, text: text)
        }
    }

    private func configureVolumeKeys(_ enabled: Bool) {
        VolumeKeyObserver.shared.onUp = { [weak vm] in vm?.previous() }
        VolumeKeyObserver.shared.onDown = { [weak vm] in vm?.next() }
        VolumeKeyObserver.shared.setEnabled(enabled)
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                vm.saveNow()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.book.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(vm.chapterTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if vm.isReflowable {
                Button { vm.sheet = .chapters } label: { Image(systemName: "list.bullet") }
            }
            // 原文修订：只有 TXT / EPUB 能改，PDF 与漫画是固定版面
            if vm.canRevise {
                Button { vm.sheet = .revisions } label: { Image(systemName: "pencil.and.outline") }
            }
            // PDF 也能全文搜，漫画没有文字就不给这个按钮
            if vm.isReflowable || vm.book.format == .pdf {
                Button { vm.sheet = .search } label: { Image(systemName: "magnifyingglass") }
            }
            Button { vm.sheet = .notes } label: {
                Image(systemName: "bookmark")
            }
            Button { showCloseConfirm = true } label: {
                Image(systemName: "xmark")
            }
        }
        .foregroundStyle(vm.settings.textColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - 底栏

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // 页码可以直接点 —— 拖滑块找某一页太慢，输数字更快
                Button {
                    jumpPageText = ""
                    showJumpPage = true
                } label: {
                    Text("\(vm.currentPage + 1)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Slider(
                    value: Binding(
                        get: { Double(vm.currentPage) },
                        set: { vm.goToPage(Int(round($0))) }
                    ),
                    in: 0...Double(max(1, vm.totalPages - 1))
                )
                Text("\(vm.totalPages)")
                    .font(.caption.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.caption)

            HStack(spacing: 0) {
                barButton("list.bullet", "目录") { vm.sheet = .chapters }
                    .disabled(!vm.isReflowable)
                barButton("textformat.size", "字体") { vm.sheet = .settings }
                barButton("paintbrush", "背景") { vm.sheet = .settings }
                directionButton
                barButton(vm.autoPlaying ? "pause.fill" : "play.fill", "自动") {
                    vm.toggleAutoPlay()
                }
                barButton(vm.speechOn ? "speaker.wave.3.fill" : "speaker.wave.2", "朗读") {
                    vm.toggleSpeech()
                }
                .disabled(!vm.canSpeak)
                barButton("character.book.closed", "查词") {
                    lookupTerm = LookupTerm(text: "")
                }
                barButton("scribble", "手写") { vm.annotationMode = true }
                barButton("note.text.badge.plus", "笔记") { showNoteComposer = true }
                barButton(vm.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark", "书签") {
                    vm.toggleBookmark()
                }
            }
        }
        .foregroundStyle(vm.settings.textColor)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(.bar)
    }

    /// 翻页方向键：漫画是「左→右 / 右→左 / 上→下」三态循环，
    /// 文字书还是「左右分页 / 上下滚动」两态。两者各自独立存，不会互相串。
    @ViewBuilder
    private var directionButton: some View {
        if vm.book.format == .comic {
            let dir = vm.settings.comicDirection
            barButton(dir.icon, dir.shortTitle) {
                vm.settings.comicDirection = dir.next
                vm.settingsDidChange()
                vm.toast = "漫画方向：" + vm.settings.comicDirection.title
            }
        } else {
            barButton(vm.settings.direction.icon, vm.settings.direction.shortTitle) {
                vm.settings.direction = (vm.settings.direction == .horizontal) ? .vertical : .horizontal
                vm.settingsDidChange()
            }
        }
    }

    private func barButton(_ systemName: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(.system(size: 17))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 自动翻页条

    private var autoPlayBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 16) {
                Button { vm.stopAutoPlay() } label: {
                    Image(systemName: "pause.circle.fill")
                        .font(.title2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("自动翻页中")
                        .font(.caption)
                    Text(String(format: "%.1f 秒 / 页", vm.settings.autoPlaySpeed))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $vm.settings.autoPlaySpeed, in: 1...60, step: 0.5)
                    .frame(width: 120)
                    .onChange(of: vm.settings.autoPlaySpeed) { _ in vm.restartAutoTimer() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    // MARK: - 播读条

    private var speechBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                Button {
                    vm.speech.isPaused ? vm.speech.resume() : vm.speech.pause()
                } label: {
                    Image(systemName: vm.speech.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.title2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.speech.isPaused ? "已暂停" : "播读中")
                        .font(.caption)
                    Text(vm.speechText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: 260, alignment: .leading)

                Slider(value: $vm.settings.speechRate, in: 0.1...1.0, step: 0.05)
                    .frame(width: 110)
                    .onChange(of: vm.settings.speechRate) { _ in vm.speechRateDidChange() }

                Button {
                    vm.stopSpeech()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }
}
