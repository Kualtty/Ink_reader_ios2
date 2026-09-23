//  墨阅 InkReader · InkReader/Views/Reader/TxtPagedReader.swift
//  功能：TXT 分页阅读器 —— 以横向翻页方式逐页呈现 TxtPaginator 的结果。
//  要点：与 TxtScrollReader 二选一，由阅读设置决定。

import SwiftUI
import UIKit

/// TXT / EPUB 左右翻页（分页）阅读器
struct TxtPagedReader: View {
    @ObservedObject var vm: ReaderViewModel
    var onSelect: (NSRange, String, TextAction) -> Void

    var body: some View {
        GeometryReader { geo in
            TabView(
                selection: Binding(
                    get: { vm.currentPage },
                    set: { vm.goToPage($0) }
                )
            ) {
                ForEach(0..<vm.pageRanges.count, id: \.self) { index in
                    pageContent(index: index, size: geo.size)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(vm.settings.backgroundColor)
            .onAppear { vm.viewSizeDidChange(geo.size) }
            .onChange(of: geo.size) { _, newSize in
                vm.viewSizeDidChange(newSize)
            }
        }
        .ignoresSafeArea()
        .onChange(of: vm.autoTick) { _, _ in
            vm.next()
        }
    }

    @ViewBuilder
    private func pageContent(index: Int, size: CGSize) -> some View {
        let range = vm.pageRanges[index]
        let ns = vm.attributedText
        let start = min(range.location, ns.length)
        let length = min(range.length, max(0, ns.length - start))
        let globalRange = NSRange(location: range.location, length: range.length)

        let attr = ns.attributedSubstring(from: NSRange(location: start, length: length))
        let highlights = vm.annotations.highlights(for: vm.book.id)
            .filter { NSIntersectionRange($0.range, globalRange).length > 0 }

        PageTextView(
            attributedText: attr,
            highlights: highlights,
            pageStart: range.location,
            backgroundColor: vm.settings.uiBackgroundColor,
            contentSignature: "\(vm.currentPageSignature)-\(highlights.count)-\(index)",
            onSelect: onSelect,
            onTap: { vm.barsVisible.toggle() }
        )
        .padding(.horizontal, vm.settings.horizontalMargin)
        .padding(.vertical, vm.settings.verticalMargin)
        .frame(width: size.width, height: size.height)
        .background(vm.settings.backgroundColor)
        .contentShape(Rectangle())
    }
}
