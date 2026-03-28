import Foundation

@MainActor
final class DocumentViewModel: ObservableObject {
    static let supportedFileExtension = "md"

    struct PresentedError: Identifiable {
        let id = UUID()
        let message: String
    }

    @Published private(set) var currentFileURL: URL?
    @Published private(set) var currentFileName: String?
    @Published private(set) var rawMarkdown = ""
    @Published private(set) var renderedHTML = ""
    @Published private(set) var baseURL: URL?
    @Published private(set) var renderedFileURL: URL?
    @Published private(set) var previewRequestID = UUID()
    @Published private(set) var isLoading = false
    @Published var presentedError: PresentedError?
    @Published var previewDiagnostics: String?
    @Published var useNativeFallback = false

    var hasDocument: Bool {
        currentFileURL != nil
    }

    var navigationTitle: String {
        currentFileName ?? "MarkdownPreview"
    }

    var isTextSearchAvailable: Bool {
        hasDocument && !useNativeFallback
    }

    private let renderer = MarkdownRenderer()
    private let fileWatcher = FileWatcher()

    private var activeSecurityScopedURL: URL?
    private var startedSecurityScopeAccess = false
    private var previewTimeoutTask: Task<Void, Never>?

    func open(url: URL) async -> Bool {
        guard Self.isSupportedMarkdownFile(url) else {
            presentedError = PresentedError(message: Self.unsupportedFileMessage(for: url))
            return false
        }

        stopFileAccess()

        let startedAccess = url.startAccessingSecurityScopedResource()
        activeSecurityScopedURL = url
        startedSecurityScopeAccess = startedAccess
        isLoading = true
        startPreviewAttempt()

        do {
            let markdown = try await loadMarkdown(from: url)
            let rendered = try renderer.render(markdown: markdown, title: url.lastPathComponent, documentURL: url)

            currentFileURL = url
            currentFileName = url.lastPathComponent
            rawMarkdown = markdown
            renderedHTML = rendered.html
            baseURL = rendered.baseURL
            renderedFileURL = rendered.fileURL
            presentedError = nil

            try configureWatcher(for: url)

            isLoading = false
            return true
        } catch {
            isLoading = false
            currentFileURL = nil
            currentFileName = nil
            rawMarkdown = ""
            renderedHTML = ""
            baseURL = nil
            renderedFileURL = nil
            presentedError = PresentedError(message: error.localizedDescription)
            previewDiagnostics = nil
            useNativeFallback = false
            stopFileAccess()
            return false
        }
    }

    func reloadCurrentDocument() async {
        guard let url = currentFileURL else { return }

        do {
            let markdown = try await loadMarkdown(from: url)
            let rendered = try renderer.render(markdown: markdown, title: url.lastPathComponent, documentURL: url)
            startPreviewAttempt()
            rawMarkdown = markdown
            renderedHTML = rendered.html
            baseURL = rendered.baseURL
            renderedFileURL = rendered.fileURL
            try configureWatcher(for: url)
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }

    func updatePreviewDiagnostics(_ message: String?) {
        previewDiagnostics = message

        if message == nil {
            previewTimeoutTask?.cancel()
            previewTimeoutTask = nil
            useNativeFallback = false
            return
        }

        let normalized = message?.lowercased() ?? ""
        if normalized.contains("failed") || normalized.contains("error") || normalized.contains("terminated") {
            previewTimeoutTask?.cancel()
            previewTimeoutTask = nil
            useNativeFallback = true
        }
    }

    private func configureWatcher(for url: URL) throws {
        try fileWatcher.startWatching(url: url) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.reloadCurrentDocument()
            }
        }
    }

    private func stopFileAccess() {
        fileWatcher.stop()
        previewTimeoutTask?.cancel()
        previewTimeoutTask = nil

        if startedSecurityScopeAccess {
            activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        }

        activeSecurityScopedURL = nil
        startedSecurityScopeAccess = false
    }

    private func loadMarkdown(from url: URL) async throws -> String {
        let path = url.path

        return try await Task.detached(priority: .userInitiated) {
            try String(contentsOfFile: path, encoding: .utf8)
        }.value
    }

    private func startPreviewAttempt() {
        previewTimeoutTask?.cancel()
        previewRequestID = UUID()
        previewDiagnostics = "Preparing web preview…"
        useNativeFallback = false

        previewTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            guard self.previewDiagnostics != nil else { return }
            self.previewDiagnostics = "Rendering your preview. Large Markdown files can take a moment."
        }
    }

    static func isSupportedMarkdownFile(_ url: URL) -> Bool {
        !url.hasDirectoryPath && url.pathExtension.caseInsensitiveCompare(supportedFileExtension) == .orderedSame
    }

    static func unsupportedFileMessage(for url: URL) -> String {
        "\"\(url.lastPathComponent)\" isn’t supported. MarkdownPreview only opens .\(supportedFileExtension) files."
    }
}
