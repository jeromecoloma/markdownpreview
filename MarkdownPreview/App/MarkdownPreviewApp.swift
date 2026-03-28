import SwiftUI

@main
struct MarkdownPreviewApp: App {
    @StateObject private var documentViewModel = DocumentViewModel()
    @StateObject private var recentFilesViewModel = RecentFilesViewModel()
    @StateObject private var previewSearchController = PreviewSearchController()

    var body: some Scene {
        WindowGroup {
            ContentView(
                documentViewModel: documentViewModel,
                recentFilesViewModel: recentFilesViewModel,
                previewSearchController: previewSearchController
            )
            .frame(minWidth: 920, minHeight: 620)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentSize)
        .commands {
            PreviewSearchCommands(previewSearchController: previewSearchController)
        }
    }
}

private struct PreviewSearchCommands: Commands {
    @ObservedObject var previewSearchController: PreviewSearchController

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()

            Button("Find…") {
                previewSearchController.showFindInterface()
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(!previewSearchController.canSearch)

            Button("Find Next") {
                previewSearchController.findNext()
            }
            .keyboardShortcut("g", modifiers: [.command])
            .disabled(!previewSearchController.canSearch)

            Button("Find Previous") {
                previewSearchController.findPrevious()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(!previewSearchController.canSearch)
        }
    }
}
