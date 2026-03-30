import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum KeyboardFocusTarget: Hashable {
    case sidebarOpenButton
    case recentFilesList
    case emptyStateOpenButton
    case preview
}

enum PreviewScrollDirection {
    case up
    case down
}

@MainActor
final class KeyboardAccessibilityController: ObservableObject {
    @Published var selectedRecentFileID: String?
    @Published private(set) var requestedFocusTarget: KeyboardFocusTarget?
    @Published private(set) var focusRequestToken = UUID()
    @Published private(set) var previewScrollToken = UUID()
    @Published private(set) var previewScrollDirection: PreviewScrollDirection?
    @Published private(set) var focusedTarget: KeyboardFocusTarget?
    @Published private(set) var canFocusRecentFiles = false
    @Published private(set) var canFocusPreview = false

    var openSelectedRecentFileAction: (() -> Void)?
    var removeSelectedRecentFileAction: (() -> Void)?

    func updateAvailability(hasRecentFiles: Bool, canFocusPreview: Bool) {
        self.canFocusRecentFiles = hasRecentFiles
        self.canFocusPreview = canFocusPreview

        if !hasRecentFiles {
            selectedRecentFileID = nil
        }
    }

    func requestFocus(_ target: KeyboardFocusTarget) {
        switch target {
        case .recentFilesList:
            guard canFocusRecentFiles else { return }
        case .preview:
            guard canFocusPreview else { return }
        case .sidebarOpenButton, .emptyStateOpenButton:
            break
        }

        requestedFocusTarget = target
        focusRequestToken = UUID()
    }

    func requestPreviewScroll(_ direction: PreviewScrollDirection) {
        guard canFocusPreview else { return }
        previewScrollDirection = direction
        previewScrollToken = UUID()
    }

    func markFocused(_ target: KeyboardFocusTarget?) {
        focusedTarget = target
    }

    func openSelectedRecentFile() {
        openSelectedRecentFileAction?()
    }

    func removeSelectedRecentFile() {
        removeSelectedRecentFileAction?()
    }
}

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
    @StateObject private var keyboardAccessibilityController = KeyboardAccessibilityController()

    var body: some Scene {
        WindowGroup {
            ContentView(
                documentViewModel: documentViewModel,
                recentFilesViewModel: recentFilesViewModel,
                previewSearchController: previewSearchController,
                keyboardAccessibilityController: keyboardAccessibilityController,
                openPanel: presentOpenPanel,
                openDocument: openDocument
            )
            .frame(minWidth: 920, minHeight: 620)
            .task {
                configureExternalFileHandling()
            }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentSize)
        .commands {
            PreviewDocumentCommands(
                documentViewModel: documentViewModel,
                openPanel: presentOpenPanel
            )
            PreviewSearchCommands(previewSearchController: previewSearchController)
            PreviewAccessibilityCommands(keyboardAccessibilityController: keyboardAccessibilityController)
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

        openDocument(url)
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = markdownTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openDocument(url)
    }

    private func openDocument(_ url: URL) {
        guard DocumentViewModel.isSupportedMarkdownFile(url) else {
            documentViewModel.presentedError = .init(
                message: DocumentViewModel.unsupportedFileMessage(for: url)
            )
            return
        }

        Task { @MainActor in
            let opened = await documentViewModel.open(url: url)
            if opened {
                withAnimation(.easeInOut(duration: 0.22)) {
                    recentFilesViewModel.add(url: url)
                }
            }
        }
    }

    private var markdownTypes: [UTType] {
        UTType(filenameExtension: DocumentViewModel.supportedFileExtension).map { [$0] } ?? []
    }
}

private struct PreviewDocumentCommands: Commands {
    @ObservedObject var documentViewModel: DocumentViewModel
    let openPanel: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…", action: openPanel)
                .keyboardShortcut("o", modifiers: [.command])
        }

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

private struct PreviewAccessibilityCommands: Commands {
    @ObservedObject var keyboardAccessibilityController: KeyboardAccessibilityController

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Focus Recent Files") {
                keyboardAccessibilityController.requestFocus(.recentFilesList)
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            .disabled(!keyboardAccessibilityController.canFocusRecentFiles)

            Button("Focus Preview") {
                keyboardAccessibilityController.requestFocus(.preview)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            .disabled(!keyboardAccessibilityController.canFocusPreview)

            Divider()

            Button("Open Selected Recent File") {
                keyboardAccessibilityController.openSelectedRecentFile()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(keyboardAccessibilityController.selectedRecentFileID == nil)

            Button("Remove Selected Recent File") {
                keyboardAccessibilityController.removeSelectedRecentFile()
            }
            .disabled(keyboardAccessibilityController.selectedRecentFileID == nil)
        }
    }
}
