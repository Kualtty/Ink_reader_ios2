import SwiftUI
import UIKit

/// 划词后的动作
enum TextAction {
    case highlight
    case note
    /// 查词（系统词典 + 网页）
    case lookup
    /// 朗读选中的这一段
    case speak
}

/// 支持划词与高亮的只读文本视图（单页）
struct PageTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let highlights: [HighlightRange]
    /// 本页首字符在全文中的偏移，用于把全局高亮换算成本地 range
    let pageStart: Int
    let backgroundColor: UIColor
    let contentSignature: String
    let onSelect: (NSRange, String, TextAction) -> Void
    var onTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = true
        textView.backgroundColor = backgroundColor
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byTruncatingTail
        textView.delegate = context.coordinator
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

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
        context.coordinator.parent = self
        uiView.backgroundColor = backgroundColor
        if context.coordinator.lastSignature != contentSignature || uiView.attributedText.length == 0 {
            uiView.attributedText = Self.decorated(
                attributedText,
                highlights: highlights,
                pageStart: pageStart
            )
            context.coordinator.lastSignature = contentSignature
        }
    }

    /// 应用高亮底色
    static func decorated(_ text: NSAttributedString,
                          highlights: [HighlightRange],
                          pageStart: Int) -> NSAttributedString {
        guard !highlights.isEmpty else { return text }
        let mutable = NSMutableAttributedString(attributedString: text)
        for highlight in highlights {
            let local = NSRange(location: highlight.start - pageStart, length: highlight.length)
            guard local.location >= 0, local.length > 0, NSMaxRange(local) <= mutable.length else { continue }
            mutable.addAttribute(
                .backgroundColor,
                value: UIColor(hex: highlight.colorHex).withAlphaComponent(0.45),
                range: local
            )
        }
        return mutable
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: PageTextView
        var lastSignature: String = ""

        init(_ parent: PageTextView) {
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

        @available(iOS 16.0, *)
        func textView(_ textView: UITextView,
                      editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0 else { return nil }
            let selected = (textView.attributedText.string as NSString).substring(with: range)

            let highlightAction = UIAction(title: "高亮", image: UIImage(systemName: "highlighter")) { _ in
                let global = NSRange(location: range.location + self.parent.pageStart, length: range.length)
                self.parent.onSelect(global, selected, .highlight)
            }
            let noteAction = UIAction(title: "笔记", image: UIImage(systemName: "note.text")) { _ in
                let global = NSRange(location: range.location + self.parent.pageStart, length: range.length)
                self.parent.onSelect(global, selected, .note)
            }
            var extras: [UIMenuElement] = []
            // 太长的选段不适合查词，词典和网页都扛不住一整段
            if selected.trimmed.count <= 30 {
                extras.append(UIAction(title: "查词", image: UIImage(systemName: "character.book.closed")) { _ in
                    self.parent.onSelect(globalRange(), selected, .lookup)
                })
            }
            extras.append(UIAction(title: "朗读", image: UIImage(systemName: "speaker.wave.2")) { _ in
                self.parent.onSelect(globalRange(), selected, .speak)
            })
            let menu = UIMenu(children: suggestedActions + [highlightAction, noteAction] + extras)
            return menu
        }

        private func globalRange(_ range: NSRange) -> NSRange {
            NSRange(location: range.location + parent.pageStart, length: range.length)
        }
    }
}
