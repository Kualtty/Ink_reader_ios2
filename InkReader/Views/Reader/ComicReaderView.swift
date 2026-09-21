import SwiftUI
import UIKit

// MARK: - 图片缓存

final class ComicImageCache {
    static let shared = ComicImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 40
        cache.totalCostLimit = 120 * 1024 * 1024
    }

    func image(at url: URL) -> UIImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    func clear() { cache.removeAllObjects() }
}

// MARK: - 可缩放单页

struct ZoomableImageView: View {
    let url: URL
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .animation(.easeOut(duration: 0.18), value: scale)
                } else {
                    ProgressView()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(max(1, lastScale * value), 5)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1.02 {
                            scale = 1
                            lastScale = 1
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard scale > 1.02 else { return }
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if scale > 1.02 {
                        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
                    } else {
                        scale = 2; lastScale = 2
                    }
                }
            }
        }
        .onAppear { load() }
        .onChange(of: url) { _ in
            image = nil
            scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
            load()
        }
    }

    private func load() {
        Task.detached(priority: .userInitiated) { [url] in
            let loaded = ComicImageCache.shared.image(at: url)
            await MainActor.run { self.image = loaded }
        }
    }
}

// MARK: - 条漫模式用的定宽图片

struct ComicPageImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear.frame(height: 400)
            }
        }
        .onAppear { load() }
        .onChange(of: url) { _ in image = nil; load() }
    }

    private func load() {
        Task.detached(priority: .userInitiated) { [url] in
            let loaded = ComicImageCache.shared.image(at: url)
            await MainActor.run { self.image = loaded }
        }
    }
}

// MARK: - 漫画阅读器容器

struct ComicReaderContainer: View {
    @ObservedObject var vm: ReaderViewModel
    @State private var topID: Int?

    private var spreads: [[Int]] {
        guard vm.settings.doublePageSpread else {
            return vm.comicImages.indices.map { [$0] }
        }
        var result: [[Int]] = []
        var index = 0
        let count = vm.comicImages.count
        if count > 0 { result.append([0]); index = 1 }
        while index < count {
            let end = min(index + 2, count)
            result.append(Array(index..<end))
            index = end
        }
        return result
    }

    private func spreadIndex(for page: Int) -> Int {
        spreads.firstIndex { $0.contains(page) } ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                // 形态只看 comicMode，不再跟文字书的 direction 共用一个开关：
                // 否则为了看条漫切成「上下」，回去读小说也变成滚动了
                if vm.settings.comicIsScroll {
                    scrollReader
                } else {
                    pagedReader
                }
            }
            .onAppear { vm.viewSizeDidChange(geo.size) }
            .onChange(of: geo.size) { vm.viewSizeDidChange($0) }
        }
        .background(vm.settings.backgroundColor)
        .ignoresSafeArea()
        .onTapGesture { vm.barsVisible.toggle() }
    }

    // MARK: 左右翻页（含日漫右→左）

    private var pagedReader: some View {
        let rtl = vm.settings.comicRTL
        return TabView(
            selection: Binding(
                get: { spreadIndex(for: vm.currentPage) },
                set: { newSpread in
                    if let first = spreads[safe: newSpread]?.first {
                        vm.goToPage(first)
                    }
                }
            )
        ) {
            ForEach(Array(spreads.enumerated()), id: \.offset) { item in
                spreadView(pages: item.element, spreadIndex: item.offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // 右→左：把整个分页容器镜像过来，翻页方向自然就反了（系统行为，不用手写手势）
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        .onChange(of: vm.autoTick) { _ in vm.next() }
    }

    @ViewBuilder
    private func spreadView(pages: [Int], spreadIndex: Int) -> some View {
        // 日漫双页展开时，页码小的那页在**右边**
        let ordered = vm.settings.comicRTL ? pages.reversed() : pages
        HStack(spacing: 0) {
            ForEach(Array(ordered), id: \.self) { page in
                ZoomableImageView(url: vm.comicImages[page])
            }
        }
        .tag(spreadIndex)
    }

    // MARK: 条漫（上下连续滚动）

    private var scrollReader: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(vm.comicImages.indices, id: \.self) { index in
                        ComicPageImage(url: vm.comicImages[index])
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $topID)
            .onChange(of: topID) { newValue in
                if let value = newValue { vm.goToPage(value) }
            }
            .onChange(of: vm.autoTick) { _ in
                let next = min(vm.currentPage + 1, max(0, vm.comicImages.count - 1))
                withAnimation(.easeOut(duration: max(0.2, vm.settings.autoPlaySpeed))) {
                    proxy.scrollTo(next, anchor: .top)
                }
                vm.goToPage(next)
                // 滚到最后一张就停，别让自动翻页空转
                if next >= vm.comicImages.count - 1 { vm.stopAutoPlay() }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
