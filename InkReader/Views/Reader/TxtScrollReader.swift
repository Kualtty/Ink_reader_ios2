//  墨阅 InkReader · InkReader/Views/Reader/TxtScrollReader.swift
//  功能：TXT 滚动阅读器 —— 连续滚动的 UITextView，用 layoutManager 反算字符偏移来定位。
//  要点：滚动模式下涂鸦按屏序号锚定。

import SwiftUI
import UIKit

/// TXT / EPUB 上下滚动阅读器
struct TxtScrollReader: UIViewRepresentable {
    let attributedText: NSAttributedString
    let highlights: [HighlightRange]
    let backgroundColor: UIColor
    let contentSignature: String
    let insets: UIEdgeInsets
    let autoTick: Int
    let autoPlaySpeed: Double
    let restoreOffset: Int
    let restoreToken: Int
    var onScrollReport: (Int, Int) -> Void
    var onSelect: (NSRange, String, TextAction) -> Void
    var onReachEnd: () -> Void
    var onTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = backgroundColor
        textView.textContainerInset = insets
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = true
        textView.delegate = context.coordinator

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        textView.addGestureRecognizer(tap)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        uiView.backgroundColor = backgroundColor
        uiView.textContainerInset = insets

        if coordinator.lastSignature != contentSignature {
            let decorated = PageTextView.decorated(
                attributedText,
                highlights: highlights,
                pageStart: 0
            )
            let selected = uiView.selectedRange
            uiView.attributedText = decorated
            uiView.selectedRange = selected
            coordinator.lastSignature = contentSignature
            coordinator.needsRestore = true
        }

        if (coordinator.needsRestore || coordinator.lastRestoreToken != restoreToken),
           uiView.bounds.height > 0 {
            coordinator.restore(to: restoreOffset, in: uiView)
            coordinator.lastRestoreToken = restoreToken
        }

        if coordinator.lastTick != autoTick {
            coordinator.lastTick = autoTick
            coordinator.scrollOneScreen(in: uiView, duration: autoPlaySpeed)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: TxtScrollReader
        var lastSignature: String = ""
        var lastTick: Int = 0
        var needsRestore = true
        var lastRestoreToken: Int = 0

        init(_ parent: TxtScrollReader) {
            self.parent = parent
        }

        @objc func handleTap() {
            parent.onTap?()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // MARK: 恢复阅读位置

        func restore(to offset: Int, in textView: UITextView) {
            guard offset > 0, textView.attributedText.length > 0 else {
                needsRestore = false
                return
            }
            let clamped = min(offset, max(0, textView.attributedText.length - 1))
            let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: clamped)
            let rect = textView.layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textView.textContainer
            )
            let target = max(0, rect.minY + textView.textContainerInset.top - textView.textContainerInset.top)
            textView.contentOffset = CGPoint(x: 0, y: target)
            needsRestore = false
        }

        // MARK: 自动翻页：向下滚动一屏

        func scrollOneScreen(in textView: UITextView, duration: Double) {
            let visible = max(1, textView.bounds.height
                              - textView.textContainerInset.top
                              - textView.textContainerInset.bottom)
            let maxOffset = max(0, textView.contentSize.height - textView.bounds.height
                                + textView.textContainerInset.bottom)
            let target = min(maxOffset, textView.contentOffset.y + visible)
            if target - textView.contentOffset.y < 2 {
                parent.onReachEnd()
                return
            }
            UIView.animate(
                withDuration: max(0.2, duration),
                delay: 0,
                options: [.curveLinear, .allowUserInteraction]
            ) {
                textView.contentOffset = CGPoint(x: 0, y: target)
            }
        }

        // MARK: UIScrollViewDelegate

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? UITextView,
                  textView.bounds.height > 0,
                  textView.attributedText.length > 0 else { return }

            let visible = max(1, textView.bounds.height
                              - textView.textContainerInset.top
                              - textView.textContainerInset.bottom)
            let containerTop = max(0, textView.contentOffset.y - textView.textContainerInset.top)
            let screenIndex = Int(round(containerTop / visible))

            let point = CGPoint(x: 0, y: containerTop)
            let charIndex = textView.layoutManager.characterIndex(
                for: point,
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            parent.onScrollReport(screenIndex, charIndex)
        }

        // MARK: UITextViewDelegate

        @available(iOS 16.0, *)
        func textView(_ textView: UITextView,
                      editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0 else { return nil }
            let selected = (textView.attributedText.string as NSString).substring(with: range)

            let highlight = UIAction(title: "高亮", image: UIImage(systemName: "highlighter")) { _ in
                self.parent.onSelect(range, selected, .highlight)
            }
            let note = UIAction(title: "笔记", image: UIImage(systemName: "note.text")) { _ in
                self.parent.onSelect(range, selected, .note)
            }
            var extras: [UIMenuElement] = []
            // 太长的选段不适合查词，词典和网页都扛不住一整段
            if selected.trimmed.count <= 30 {
                extras.append(UIAction(title: "查词", image: UIImage(systemName: "character.book.closed")) { _ in
                    self.parent.onSelect(range, selected, .lookup)
                })
            }
            extras.append(UIAction(title: "朗读", image: UIImage(systemName: "speaker.wave.2")) { _ in
                self.parent.onSelect(range, selected, .speak)
            })
            extras.append(UIAction(title: "编辑原文", image: UIImage(systemName: "pencil.and.outline")) { _ in
                self.parent.onSelect(range, selected, .revise)
            })
            return UIMenu(children: suggestedActions + [highlight, note] + extras)
        }
    }
}

/// SwiftUI 包装层：负责把 VM 状态转成 representable 参数
struct TxtScrollReaderContainer: View {
    @ObservedObject var vm: ReaderViewModel
    var onSelect: (NSRange, String, TextAction) -> Void

    var body: some View {
        GeometryReader { geo in
            TxtScrollReader(
                attributedText: vm.attributedText,
                highlights: vm.annotations.highlights(for: vm.book.id),
                backgroundColor: vm.settings.uiBackgroundColor,
                contentSignature: vm.currentPageSignature,
                insets: UIEdgeInsets(
                    top: vm.settings.verticalMargin,
                    left: vm.settings.horizontalMargin,
                    bottom: vm.settings.verticalMargin + 40,
                    right: vm.settings.horizontalMargin
                ),
                autoTick: vm.autoTick,
                autoPlaySpeed: vm.settings.autoPlaySpeed,
                restoreOffset: vm.jumpToken == 0 ? (Int(vm.book.locator) ?? 0) : vm.jumpOffset,
                restoreToken: vm.jumpToken,
                onScrollReport: { screen, offset in
                    vm.scrollDidReport(screenIndex: screen, topOffset: offset)
                },
                onSelect: onSelect,
                onReachEnd: { vm.stopAutoPlay() },
                onTap: { vm.barsVisible.toggle() }
            )
            .ignoresSafeArea()
            .onAppear { vm.viewSizeDidChange(geo.size) }
            .onChange(of: geo.size) { vm.viewSizeDidChange($0) }
        }
    }
}
