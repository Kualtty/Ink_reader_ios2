//  墨阅 InkReader · InkReader/Views/Reader/PdfReaderView.swift
//  功能：PDF 阅读器 —— PDFKit 视图 + 页码跳转 + 涂鸦层 + 搜索入口。
//  要点：PDF 是固定版面，不做原文修订。

import PDFKit
import SwiftUI
import UIKit

/// PDFKit 阅读视图（左右 / 上下翻页，页码同步，自动翻页）
struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    var direction: PDFDisplayDirection
    var backgroundColor: UIColor
    var autoTick: Int
    var doublePageSpread: Bool
    /// 搜索命中的高亮；配合 token 使用（同一个 selection 重复设置也该再滚一次）
    var highlight: PDFSelection?
    var highlightToken: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displaysPageBreaks = false
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = direction
        pdfView.backgroundColor = backgroundColor
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.pageShadowsEnabled = true
        context.coordinator.attach(to: pdfView)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if uiView.document !== document {
            uiView.document = document
        }
        uiView.backgroundColor = backgroundColor
        uiView.displayDirection = direction
        uiView.displayMode = doublePageSpread ? .twoUp : .singlePage
        uiView.autoScales = true

        // 外部跳转（进度条 / 目录 / 书签）
        if coordinator.lastSyncedPage != currentPage,
           let page = document.page(at: currentPage),
           uiView.currentPage !== page {
            uiView.go(to: page)
            coordinator.lastSyncedPage = currentPage
        }

        // 自动翻页
        if coordinator.lastTick != autoTick {
            coordinator.lastTick = autoTick
            if uiView.canGoToNextPage {
                uiView.goToNextPage(nil)
            } else {
                NotificationCenter.default.post(name: .inkAutoPlayReachedEnd, object: nil)
            }
        }

        // 搜索命中高亮：token 变了才动，避免每帧重设把用户自己的选区冲掉
        if coordinator.lastHighlightToken != highlightToken {
            coordinator.lastHighlightToken = highlightToken
            coordinator.lastHighlight = highlight
            uiView.highlightedSelections = highlight.map { [$0] }
            if let highlight {
                uiView.setCurrentSelection(highlight, animate: true)
                uiView.scrollSelectionToVisible(nil)
            }
        }
    }

    final class Coordinator: NSObject {
        var parent: PDFKitView
        var lastTick: Int = 0
        var lastSyncedPage: Int = -1
        var lastHighlightToken: Int = 0
        weak var lastHighlight: PDFSelection?

        init(_ parent: PDFKitView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePageChanged(_:)),
                name: .PDFViewPageChanged,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(to pdfView: PDFView) {
            if let page = pdfView.document?.page(at: parent.currentPage) {
                pdfView.go(to: page)
            }
            lastSyncedPage = parent.currentPage
        }

        @objc private func handlePageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let document = pdfView.document,
                  let page = pdfView.currentPage else { return }
            let index = document.index(for: page)
            guard index != lastSyncedPage else { return }
            lastSyncedPage = index
            DispatchQueue.main.async {
                self.parent.currentPage = index
            }
        }
    }
}

extension Notification.Name {
    static let inkAutoPlayReachedEnd = Notification.Name("ink.autoPlay.reachedEnd")
}

struct PdfReaderContainer: View {
    @ObservedObject var vm: ReaderViewModel

    var body: some View {
        Group {
            if let document = vm.pdfDocument {
                PDFKitView(
                    document: document,
                    currentPage: Binding(
                        get: { vm.currentPage },
                        set: { vm.goToPage($0) }
                    ),
                    direction: vm.settings.direction == .horizontal ? .horizontal : .vertical,
                    backgroundColor: vm.settings.uiBackgroundColor,
                    autoTick: vm.autoTick,
                    doublePageSpread: vm.settings.doublePageSpread,
                    highlight: vm.pdfHighlight,
                    highlightToken: vm.pdfHighlightToken
                )
            } else {
                ProgressView()
            }
        }
        .ignoresSafeArea()
        .onTapGesture { vm.barsVisible.toggle() }
        .onReceive(NotificationCenter.default.publisher(for: .inkAutoPlayReachedEnd)) { _ in
            vm.stopAutoPlay()
        }
    }
}
