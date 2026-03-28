import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var openFilesHandler: (([URL]) -> Void)?
    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }

        guard let openFilesHandler else {
            pendingURLs.append(contentsOf: urls)
            return
        }

        openFilesHandler(urls)
    }

    func flushPendingURLsIfNeeded() {
        guard let openFilesHandler, !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        openFilesHandler(urls)
    }
}

@main
struct MarkdownPreviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            .task {
                configureExternalFileHandling()
            }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentSize)
        .commands {
            PreviewDocumentCommands(documentViewModel: documentViewModel)
            PreviewSearchCommands(previewSearchController: previewSearchController)
        }
    }

    private func configureExternalFileHandling() {
        guard appDelegate.openFilesHandler == nil else { return }

        appDelegate.openFilesHandler = { urls in
            Task { @MainActor in
                await openIncomingFiles(urls)
            }
        }
        appDelegate.flushPendingURLsIfNeeded()
    }

    @MainActor
    private func openIncomingFiles(_ urls: [URL]) async {
        guard let url = urls.first(where: DocumentViewModel.isSupportedMarkdownFile(_:)) else {
            if let firstURL = urls.first {
                documentViewModel.presentedError = .init(
                    message: DocumentViewModel.unsupportedFileMessage(for: firstURL)
                )
            }
            return
        }

        let opened = await documentViewModel.open(url: url)
        if opened {
            withAnimation(.easeInOut(duration: 0.22)) {
                recentFilesViewModel.add(url: url)
            }
        }
    }
}

private struct PreviewDocumentCommands: Commands {
    @ObservedObject var documentViewModel: DocumentViewModel

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Reload File") {
                Task {
                    await documentViewModel.reloadCurrentDocument()
                }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(!documentViewModel.hasDocument)
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
