import SwiftUI

@main
struct MarkdownPreviewApp: App {
    @StateObject private var documentViewModel = DocumentViewModel()
    @StateObject private var recentFilesViewModel = RecentFilesViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(
                documentViewModel: documentViewModel,
                recentFilesViewModel: recentFilesViewModel
            )
            .frame(minWidth: 920, minHeight: 620)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentSize)
    }
}
