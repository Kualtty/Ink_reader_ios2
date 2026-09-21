//  墨阅 InkReader · InkReader/Views/Reader/ReaderViewModel.swift
//  功能：阅读器视图模型 —— 装载书籍、分页、翻页、标注、播读、修订、涂鸦的业务中枢。
//  要点：构造参数含 library / annotations / revisions / pages 四个 Store，新增 Store 要同步改这里与容器。

import Combine
import Foundation
import PDFKit
import SwiftUI
import UIKit

enum ReaderSheet: Identifiable {
    case settings
    case notes
    case chapters
    case search
    case jump
    /// 原文修订记录 / 失效标注
    case revisions

    var id: String {
        switch self {
        case .settings: return "settings"
        case .notes: return "notes"
        case .chapters: return "chapters"
        case .search: return "search"
        case .jump: return "jump"
        case .revisions: return "revisions"
        }
    }
}

@MainActor
final class ReaderViewModel: ObservableObject {
    // MARK: 依赖
    private let library: LibraryStore
    let annotations: AnnotationStore
    /// 原文修订记录（改原文后平移标注、撤销、失效标注找回）
    let revisions: RevisionStore
    /// 漫画页序（合并 / 拆分 / 手动排序后就靠它）
    let pages: ComicPageStore

    // MARK: 书籍
    private(set) var book: Book

    // MARK: 内容
    @Published var settings: ReadingSettings
    @Published var isLoading = true
    @Published var statusText: String = "加载中…"

    @Published var plainText: String = ""
    @Published var attributedText: NSAttributedString = NSAttributedString(string: "")
    @Published var pageRanges: [NSRange] = []
    @Published var chapters: [Chapter] = []

    @Published var pdfDocument: PDFDocument?
    @Published var comicImages: [URL] = []

    /// 搜索命中的那处高亮（PDF）。PDFSelection 是类，靠 token 变化触发刷新。
    @Published var pdfHighlight: PDFSelection?
    @Published var pdfHighlightToken: Int = 0

    // MARK: 播读
    /// 播读引擎。刻意不标 @MainActor（AVSpeechSynthesizerDelegate 是 ObjC 协议），
    /// 对外只暴露 speechOn / speechText 两个已发布状态给界面用。
    let speech = SpeechService()
    @Published var speechOn = false
    @Published var speechText = ""

    // MARK: 位置
    @Published var currentPage: Int = 0
    @Published var totalPages: Int = 1
    @Published var scrollScreenIndex: Int = 0
    @Published var topCharacterOffset: Int = 0
    @Published var viewSize: CGSize = .zero
    /// 显式跳转请求（章节 / 书签 / 搜索）
    @Published var jumpOffset: Int = 0
    @Published var jumpToken: Int = 0

    // MARK: UI 状态
    @Published var barsVisible = false
    @Published var annotationMode = false
    @Published var autoPlaying = false
    @Published var autoTick = 0
    @Published var sheet: ReaderSheet?
    @Published var toast: String?

    private var autoTimer: Timer?
    private var saveWork: DispatchWorkItem?
    private var relayoutWork: DispatchWorkItem?
    private var lastLayoutSignature: String = ""
    /// SwiftUI 不会观察嵌套的 ObservableObject，这里把播读引擎的变化转发出来，
    /// 否则「暂停 / 继续」按钮的图标不会跟着变
    /// 播读引擎的变化要转发（SwiftUI 观察不到嵌套的 ObservableObject）
    private var speechBridge: AnyCancellable?
    private var revisionBridge: AnyCancellable?

    init(book: Book,
         library: LibraryStore,
         annotations: AnnotationStore,
         revisions: RevisionStore,
         pages: ComicPageStore) {
        self.book = book
        self.library = library
        self.annotations = annotations
        self.revisions = revisions
        self.pages = pages
        self.settings = library.settings
        self.totalPages = max(1, book.totalPages)
        if let raw = Int(book.locator) {
            self.currentPage = min(max(0, raw), max(0, totalPages - 1))
        }
        speechBridge = speech.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        revisionBridge = revisions.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    deinit {
        autoTimer?.invalidate()
        saveWork?.cancel()
        relayoutWork?.cancel()
        speech.stop()
    }

    var isReflowable: Bool { book.format.isReflowable }
    var isPaged: Bool { !isReflowable || settings.direction == .horizontal }

    /// 排版指纹：变化时刷新富文本
    var currentPageSignature: String {
        "\(settings.fontSize)-\(settings.lineSpacing)-\(settings.characterSpacing)-\(settings.paragraphSpacing)-\(settings.fontName)-\(settings.isBold)-\(settings.alignment.rawValue)-\(settings.foregroundHex)-\(settings.horizontalMargin)-\(settings.verticalMargin)"
    }

    /// 手写涂鸦锚点
    var drawingAnchor: String {
        switch book.format {
        case .comic: return "c\(currentPage)"
        case .pdf: return "d\(currentPage)"
        default:
            return isPaged ? "p\(currentPage)" : "s\(scrollScreenIndex)"
        }
    }

    /// 阅读位置字符串
    var currentLocator: String {
        switch book.format {
        case .comic, .pdf: return "\(currentPage)"
        default:
            if isPaged {
                guard currentPage < pageRanges.count else { return "0" }
                return "\(pageRanges[currentPage].location)"
            }
            return "\(topCharacterOffset)"
        }
    }

    var progress: Double {
        guard totalPages > 1 else { return 0 }
        return min(1, max(0, Double(currentPage) / Double(totalPages - 1)))
    }

    var chapterTitle: String {
        guard isReflowable, !chapters.isEmpty else {
            return "第 \(currentPage + 1) / \(totalPages) 页"
        }
        let offset = isPaged
            ? (currentPage < pageRanges.count ? pageRanges[currentPage].location : 0)
            : topCharacterOffset
        let idx = ChapterParser.index(of: offset, in: chapters)
        return chapters[idx].title
    }

    // MARK: - 加载

    func load() async {
        isLoading = true
        statusText = "加载中…"

        switch book.format {
        case .txt, .epub:
            await loadText()
        case .pdf:
            loadPDF()
        case .comic:
            await loadComic()
        }
    }

    private func loadText() async {
        statusText = "解析文本…"
        let url = book.fileURL
        let text = await Task.detached(priority: .userInitiated) { () -> String in
            guard let data = try? Data(contentsOf: url) else { return "" }
            return TextEncodingDetector.decode(data) ?? String(decoding: data, as: UTF8.self)
        }.value

        guard !text.isEmpty else {
            statusText = "无法读取该文本"
            isLoading = false
            return
        }
        plainText = text
        chapters = ChapterParser.parse(text: text)
        statusText = "排版中…"
        relayout(force: true)
    }

    private func loadPDF() {
        statusText = "打开 PDF…"
        let document = PDFDocument(url: book.fileURL)
        pdfDocument = document
        totalPages = max(1, document?.pageCount ?? book.totalPages)
        currentPage = min(max(0, Int(book.locator) ?? 0), totalPages - 1)
        isLoading = false
    }

    private func loadComic() async {
        statusText = "解压漫画…"
        let bookCopy = book
        let store = pages
        let images = await Task.detached(priority: .userInitiated) { () -> [URL] in
            store.pages(for: bookCopy)
        }.value
        comicImages = images
        totalPages = max(1, images.count)
        currentPage = min(max(0, Int(book.locator) ?? 0), totalPages - 1)
        isLoading = false
    }

    // MARK: - 重排

    /// 视图尺寸变化（首次出现 / 旋转）。做一次去抖，避免频繁重排。
    func viewSizeDidChange(_ size: CGSize) {
        viewSize = size
        relayoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.relayout()
        }
        relayoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func relayout(force: Bool = false) {
        guard isReflowable, !plainText.isEmpty else { return }
        // 尺寸尚未确定时跳过，viewSizeDidChange 会在拿到真实尺寸后补一次
        guard viewSize.width > 1, viewSize.height > 1 else { return }
        let signature = "\(viewSize.width)x\(viewSize.height)|\(settings.fontSize)|\(settings.lineSpacing)|\(settings.characterSpacing)|\(settings.paragraphSpacing)|\(settings.fontName)|\(settings.isBold)|\(settings.horizontalMargin)|\(settings.verticalMargin)|\(settings.alignment.rawValue)"
        if !force, signature == lastLayoutSignature { return }
        lastLayoutSignature = signature

        let attr = ChapterParser.attributedText(from: plainText, chapters: chapters, settings: settings)
        attributedText = attr

        let pageSize = settings.contentSize(in: viewSize)

        if settings.direction == .horizontal {
            statusText = "分页中…"
            isLoading = true
            TxtPaginator.paginate(attr, pageSize: pageSize) { [weak self] ranges in
                guard let self else { return }
                self.pageRanges = ranges
                self.totalPages = max(1, ranges.count)
                self.currentPage = TxtPaginator.pageIndex(of: Int(self.book.locator) ?? 0, in: ranges)
                self.isLoading = false
            }
        } else {
            // 滚动模式：只需估算总屏数
            let height = attr.boundingRect(
                with: CGSize(width: pageSize.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height
            totalPages = max(1, Int(ceil(height / max(1, pageSize.height))))
            let offset = Int(book.locator) ?? 0
            topCharacterOffset = min(offset, max(0, plainText.count))
            scrollScreenIndex = 0
            isLoading = false
        }
    }

    // MARK: - 跳转

    func goToPage(_ page: Int) {
        let clamped = min(max(0, page), max(0, totalPages - 1))
        currentPage = clamped
        scheduleSave()
    }

    func goToLocator(_ locator: String) {
        guard let value = Int(locator) else { return }
        if isReflowable {
            topCharacterOffset = value
            if !pageRanges.isEmpty {
                currentPage = TxtPaginator.pageIndex(of: value, in: pageRanges)
            }
        } else {
            currentPage = min(max(0, value), max(0, totalPages - 1))
        }
        scheduleSave()
    }

    /// 跳转到指定字符偏移（章节 / 搜索结果）
    func jumpToOffset(_ offset: Int) {
        let clamped = min(max(0, offset), max(0, (plainText as NSString).length))
        jumpOffset = clamped
        jumpToken += 1
        topCharacterOffset = clamped
        if !pageRanges.isEmpty {
            currentPage = TxtPaginator.pageIndex(of: clamped, in: pageRanges)
        }
        scheduleSave()
    }

    /// 把搜索命中的那一段标出来（传 nil 就是清掉）
    func setPdfHighlight(_ selection: PDFSelection?) {
        pdfHighlight = selection
        pdfHighlightToken += 1
    }

    // MARK: - 播读（从当前位置一路读下去）

    /// 漫画没有文字，读不了
    var canSpeak: Bool { book.format != .comic }

    func toggleSpeech() {
        speechOn ? stopSpeech() : startSpeech()
    }

    func startSpeech() {
        guard canSpeak else { toast = "漫画没有可朗读的文字"; return }
        let chunks = buildSpeechChunks()
        guard !chunks.isEmpty else { toast = "这里没有可朗读的文字"; return }

        speech.apply(
            rate: Float(settings.speechRate),
            voiceIdentifier: settings.speechVoiceId.isEmpty ? nil : settings.speechVoiceId
        )
        speech.onChunkStart = { [weak self] chunk in self?.speechDidStart(chunk) }
        speech.onFinish = { [weak self] in self?.stopSpeech() }
        speech.start(chunks)
        speechOn = true
        speechText = chunks.first?.text ?? ""
    }

    func stopSpeech() {
        speech.stop()
        speechOn = false
        speechText = ""
    }

    /// 只朗读划选的那一小段（划词菜单里的「朗读」）
    func speakSelection(_ text: String) {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }
        speech.apply(
            rate: Float(settings.speechRate),
            voiceIdentifier: settings.speechVoiceId.isEmpty ? nil : settings.speechVoiceId
        )
        speech.onChunkStart = { [weak self] chunk in self?.speechText = chunk.text }
        speech.onFinish = { [weak self] in self?.stopSpeech() }
        speech.start([SpeechChunk(text: trimmed, offset: nil, page: nil)])
        speechOn = true
        speechText = trimmed
    }

    /// 播读调速：正在读的不打断，下一句生效
    func speechRateDidChange() {
        guard speechOn else { return }
        speech.apply(rate: Float(settings.speechRate))
    }

    /// 从当前位置往后取要读的内容。文本书按句切，PDF 一页一段。
    private func buildSpeechChunks() -> [SpeechChunk] {
        switch book.format {
        case .comic:
            return []
        case .pdf:
            guard let doc = pdfDocument else { return [] }
            let end = min(totalPages, currentPage + 200)
            var chunks: [SpeechChunk] = []
            var page = currentPage
            while page < end {
                if let text = doc.page(at: page)?.string, !text.trimmed.isEmpty {
                    chunks.append(SpeechChunk(text: text, offset: nil, page: page))
                }
                page += 1
            }
            return chunks
        default:
            let start = isPaged && currentPage < pageRanges.count
                ? pageRanges[currentPage].location
                : topCharacterOffset
            let ns = plainText as NSString
            let from = min(max(0, start), ns.length)
            return SpeechService.split(text: ns.substring(from: from), baseOffset: from)
        }
    }

    /// 读到哪就跟到哪：PDF 同步页码，文本分页模式同步页
    private func speechDidStart(_ chunk: SpeechChunk) {
        speechText = chunk.text
        if let page = chunk.page {
            if page != currentPage { goToPage(page) }
            return
        }
        guard isPaged, let offset = chunk.offset, !pageRanges.isEmpty else { return }
        let target = TxtPaginator.pageIndex(of: offset, in: pageRanges)
        if target != currentPage { currentPage = target }
    }

    func next() {
        guard currentPage < totalPages - 1 else {
            stopAutoPlay()
            return
        }
        goToPage(currentPage + 1)
    }

    func previous() {
        guard currentPage > 0 else { return }
        goToPage(currentPage - 1)
    }

    // MARK: - 自动翻页

    func toggleAutoPlay() {
        autoPlaying ? stopAutoPlay() : startAutoPlay()
    }

    func startAutoPlay() {
        autoPlaying = true
        barsVisible = false
        restartAutoTimer()
    }

    func stopAutoPlay() {
        autoPlaying = false
        autoTimer?.invalidate()
        autoTimer = nil
    }

    func restartAutoTimer() {
        autoTimer?.invalidate()
        autoTimer = nil
        guard autoPlaying else { return }
        let interval = max(0.5, settings.autoPlaySpeed)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.autoTick += 1
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoTimer = timer
    }

    // MARK: - 设置变更

    func settingsDidChange() {
        library.settings = settings
        if isReflowable {
            relayout(force: true)
        }
        if autoPlaying { restartAutoTimer() }
        scheduleSave()
    }

    // MARK: - 摘录 / 书签 / 笔记

    func currentExcerpt(maxLength: Int = 60) -> String {
        switch book.format {
        case .comic:
            return "第 \(currentPage + 1) 页"
        case .pdf:
            if let page = pdfDocument?.page(at: currentPage) {
                return String((page.string ?? "").prefix(maxLength))
            }
            return "第 \(currentPage + 1) 页"
        default:
            guard currentPage < pageRanges.count else { return "" }
            let range = pageRanges[currentPage]
            let ns = plainText as NSString
            let safe = NSRange(location: range.location, length: min(range.length, max(0, ns.length - range.location)))
            return String(ns.substring(with: safe).prefix(maxLength))
                .replacingOccurrences(of: "\n", with: " ")
        }
    }

    func toggleBookmark() {
        annotations.toggleBookmark(
            bookId: book.id,
            page: currentPage,
            locator: currentLocator,
            excerpt: currentExcerpt()
        )
        toast = annotations.isBookmarked(bookId: book.id, locator: currentLocator) ? "已添加书签" : "已移除书签"
    }

    var isCurrentPageBookmarked: Bool {
        annotations.isBookmarked(bookId: book.id, locator: currentLocator)
    }

    // MARK: - 原文修订

    /// PDF 与漫画是固定版面，改不了原文
    var canRevise: Bool { isReflowable }

    func applyRevision(range: NSRange, replacement: String) {
        guard canRevise else { toast = "PDF / 漫画是固定版面，改不了原文"; return }
        let ns = plainText as NSString
        let loc = min(max(0, range.location), ns.length)
        let len = min(max(0, range.length), ns.length - loc)
        let oldText = ns.substring(with: NSRange(location: loc, length: len))
        guard replacement != oldText else { toast = "原文没有改动"; return }

        let record = TextRevision(
            bookId: book.id,
            location: loc,
            oldLength: len,
            oldText: oldText,
            newText: replacement
        )
        let delta = (replacement as NSString).length - len
        let next = revisions.apply(record, to: plainText, annotations: annotations)

        // 当前读到哪也要跟着平移，不然改完会莫名跳到别处
        var offset = isPaged && currentPage < pageRanges.count
            ? pageRanges[currentPage].location
            : topCharacterOffset
        if offset >= loc + len {
            offset += delta
        } else if offset > loc {
            offset = loc
        }
        book.locator = String(max(0, offset))
        topCharacterOffset = max(0, offset)
        commitRevisedText(next)
        toast = delta == 0 ? "已修订原文" : "已修订原文（长度 \(delta > 0 ? "+" : "")\(delta)）"
    }

    func undoLastRevision() {
        guard canRevise else { return }
        guard let next = revisions.undoLast(bookId: book.id, text: plainText, annotations: annotations) else {
            toast = "没有可撤销的修订"
            return
        }
        commitRevisedText(next)
        toast = "已撤销上一次修订"
    }

    func relocate(_ orphan: OrphanAnnotation) {
        if revisions.relocate(orphan, in: plainText, annotations: annotations) {
            toast = "已重新定位"
        } else {
            toast = "在新原文里没找到这段文字"
        }
    }

    func dropOrphan(_ orphan: OrphanAnnotation) {
        revisions.dropOrphan(orphan)
    }

    /// 把改后的全文写回文件、重算章节、重排
    private func commitRevisedText(_ text: String) {
        plainText = text
        chapters = ChapterParser.parse(text: text)
        try? text.write(to: book.fileURL, atomically: true, encoding: .utf8)
        book.fileSize = Storage.fileSize(at: book.fileURL)
        library.update(book)
        relayout(force: true)
        saveNow()
    }

    // MARK: - 保存进度

    func scrollDidReport(screenIndex: Int, topOffset: Int) {
        scrollScreenIndex = screenIndex
        topCharacterOffset = topOffset
        if currentPage != screenIndex { currentPage = screenIndex }
        scheduleSave()
    }

    func scheduleSave() {
        saveWork?.cancel()
        let snapshot = currentLocator
        let snapshotProgress = progress
        let total = totalPages
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.book.locator = snapshot
            self.book.progress = snapshotProgress
            self.book.totalPages = total
            self.book.lastReadAt = Date()
            self.library.update(self.book)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        book.locator = currentLocator
        book.progress = progress
        book.totalPages = totalPages
        book.lastReadAt = Date()
        library.update(book)
    }
}
