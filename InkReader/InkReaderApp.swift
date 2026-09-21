import SwiftUI

@main
struct InkReaderApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var annotations = AnnotationStore()
    @StateObject private var collections = CollectionStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(library)
                .environmentObject(annotations)
                .environmentObject(collections)
                .onAppear {
                    Storage.ensureDirectories()
                    let imported = BookImporter.importInboxFiles()
                    for book in imported { library.add(book) }
                    UIApplication.shared.isIdleTimerDisabled = library.settings.keepScreenOn
                }
                .onChange(of: library.settings.keepScreenOn) { enabled in
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
