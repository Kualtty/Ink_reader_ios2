//  墨阅 InkReader · InkReader/InkReaderApp.swift
//  功能：App 入口 —— 创建全局 Store（书架 / 收藏夹 / 标注 / 修订 / 漫画页序）并以 environmentObject 注入整棵视图树。
//  要点：全局 Store 只在这里 new 一次，其它页面一律用 @EnvironmentObject 取，不要自己再建实例。

import SwiftUI

@main
struct InkReaderApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var annotations = AnnotationStore()
    @StateObject private var collections = CollectionStore()
    @StateObject private var revisions = RevisionStore()
    @StateObject private var pages = ComicPageStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(library)
                .environmentObject(annotations)
                .environmentObject(collections)
                .environmentObject(revisions)
                .environmentObject(pages)
                .onAppear {
                    Storage.ensureDirectories()
                    let imported = BookImporter.importInboxFiles()
                    for book in imported { library.add(book) }
                    UIApplication.shared.isIdleTimerDisabled = library.settings.keepScreenOn
                }
                .onChange(of: library.settings.keepScreenOn) { _, enabled in
                    UIApplication.shared.isIdleTimerDisabled = enabled
                }
        }
    }
}

private struct AppRootView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        LibraryView()
            .preferredColorScheme(library.settings.theme.isDark ? ColorScheme.dark : nil)
    }
}
