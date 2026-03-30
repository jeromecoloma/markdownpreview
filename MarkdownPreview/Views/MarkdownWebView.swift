import AppKit
import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let fileURL: URL?
    let requestID: UUID
    let isSearchAvailable: Bool
    let searchController: PreviewSearchController
    let focusRequestToken: UUID
    let onFileDrop: @MainActor (URL) -> Void
    let onDropStateChanged: @MainActor (FileDropState) -> Void
    let isFileSupported: (URL) -> Bool
    let onDiagnostics: @MainActor (String?) -> Void

    private let topContentInset: CGFloat = 20

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onFileDrop: onFileDrop,
            onDropStateChanged: onDropStateChanged,
            onDiagnostics: onDiagnostics
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = DropReceivingWebView(frame: .zero, configuration: configuration)
        context.coordinator.isAttached = true
        context.coordinator.searchController = searchController
        webView.navigationDelegate = context.coordinator
        webView.dropHandler = context.coordinator.handleDroppedFile
        webView.dropStateHandler = context.coordinator.updateDropState
        webView.fileValidator = isFileSupported
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityLabel("Markdown preview")
        webView.setAccessibilityRole(.group)
        configureScrollViewIfNeeded(for: webView)
        searchController.setSearchAvailable(isSearchAvailable)
        searchController.register(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if let webView = webView as? DropReceivingWebView {
            webView.dropHandler = context.coordinator.handleDroppedFile
            webView.dropStateHandler = context.coordinator.updateDropState
            webView.fileValidator = isFileSupported
        }

        context.coordinator.onFileDrop = onFileDrop
        context.coordinator.onDropStateChanged = onDropStateChanged
        context.coordinator.onDiagnostics = onDiagnostics
        context.coordinator.topContentInset = topContentInset
        context.coordinator.searchController = searchController
        context.coordinator.isAttached = true
        configureScrollViewIfNeeded(for: webView)
        if context.coordinator.lastFocusRequestToken != focusRequestToken {
            context.coordinator.lastFocusRequestToken = focusRequestToken
            context.coordinator.focus(webView)
        }
        searchController.setSearchAvailable(isSearchAvailable)
        searchController.register(webView: webView)

        guard
            context.coordinator.lastHTML != html ||
            context.coordinator.lastBaseURL != baseURL ||
            context.coordinator.lastFileURL != fileURL ||
            context.coordinator.lastRequestID != requestID
        else {
            return
        }

        context.coordinator.lastHTML = html
        context.coordinator.lastBaseURL = baseURL
        context.coordinator.lastFileURL = fileURL
        context.coordinator.lastRequestID = requestID
        context.coordinator.report("Loading preview…", requestID: requestID)

        let navigation: WKNavigation?
        if let fileURL {
            navigation = webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else {
            navigation = webView.loadHTMLString(html, baseURL: baseURL)
        }

        context.coordinator.beginNavigation(navigation, requestID: requestID)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.isAttached = false
        webView.navigationDelegate = nil
        webView.stopLoading()

        if let webView = webView as? DropReceivingWebView {
            webView.dropHandler = nil
            webView.dropStateHandler = nil
            webView.fileValidator = nil
        }

        coordinator.searchController?.setSearchAvailable(false)
        coordinator.searchController?.unregister(webView: webView)
    }

    private func configureScrollViewIfNeeded(for webView: WKWebView) {
        let configure = {
            guard let scrollView = webView.enclosingScrollView else { return }
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets = NSEdgeInsets(top: topContentInset, left: 0, bottom: 0, right: 0)
            scrollView.scrollerInsets = NSEdgeInsets(top: topContentInset, left: 0, bottom: 0, right: 0)
        }

        if webView.enclosingScrollView != nil {
            configure()
        } else {
            DispatchQueue.main.async(execute: configure)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""
        var lastBaseURL: URL?
        var lastFileURL: URL?
        var lastRequestID = UUID()
        var activeRequestID = UUID()
        var isAttached = true
        var onFileDrop: @MainActor (URL) -> Void
        var onDropStateChanged: @MainActor (FileDropState) -> Void
        var onDiagnostics: @MainActor (String?) -> Void
        var topContentInset: CGFloat = 20
        var lastFocusRequestToken = UUID()
        weak var searchController: PreviewSearchController?
        private var navigationRequestIDs: [ObjectIdentifier: UUID] = [:]

        init(
            onFileDrop: @escaping @MainActor (URL) -> Void,
            onDropStateChanged: @escaping @MainActor (FileDropState) -> Void,
            onDiagnostics: @escaping @MainActor (String?) -> Void
        ) {
            self.onFileDrop = onFileDrop
            self.onDropStateChanged = onDropStateChanged
            self.onDiagnostics = onDiagnostics
        }

        func beginNavigation(_ navigation: WKNavigation?, requestID: UUID) {
            activeRequestID = requestID

            if let navigation {
                navigationRequestIDs[ObjectIdentifier(navigation)] = requestID
            }
        }

        func handleDroppedFile(_ url: URL) {
            Task { @MainActor in
                onFileDrop(url)
            }
        }

        func updateDropState(_ state: FileDropState) {
            Task { @MainActor in
                onDropStateChanged(state)
            }
        }

        func focus(_ webView: WKWebView) {
            DispatchQueue.main.async {
                webView.window?.makeFirstResponder(webView)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            report("Starting web preview…", for: navigation)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            resetScrollPosition(in: webView, navigation: navigation)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report("Navigation failed: \(error.localizedDescription)", for: navigation)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report("Preview failed to start: \(error.localizedDescription)", for: navigation)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            report("Web preview failed because the web content process terminated.", requestID: activeRequestID)
        }

        func report(_ message: String?, for navigation: WKNavigation?) {
            report(message, requestID: requestID(for: navigation))
        }

        func report(_ message: String?, requestID: UUID? = nil) {
            guard isAttached else {
                return
            }

            guard requestID == nil || requestID == activeRequestID else {
                return
            }

            Task { @MainActor in
                onDiagnostics(message)
            }
        }

        private func resetScrollPosition(in webView: WKWebView, navigation: WKNavigation?) {
            guard requestID(for: navigation) == activeRequestID else {
                return
            }

            if let scrollView = webView.enclosingScrollView {
                let point = NSPoint(x: 0, y: -topContentInset)
                scrollView.contentView.scroll(to: point)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }

            let script = """
            (() => {
              const scrollingElement = document.scrollingElement || document.documentElement || document.body;
              if (scrollingElement) {
                scrollingElement.scrollTop = 0;
                scrollingElement.scrollLeft = 0;
              }
              window.scrollTo(0, 0);
              return !!document.getElementById('markdown-root');
            })();
            """

            let requestID = activeRequestID
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self else { return }
                guard requestID == self.activeRequestID else { return }

                if let hasMarkdownRoot = result as? Bool, hasMarkdownRoot {
                    self.report(nil, requestID: requestID)
                } else {
                    self.report("Preview loaded, but the rendered document container was missing.", requestID: requestID)
                }
            }
        }

        private func requestID(for navigation: WKNavigation?) -> UUID? {
            guard let navigation else { return activeRequestID }
            return navigationRequestIDs[ObjectIdentifier(navigation)] ?? activeRequestID
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}

private final class DropReceivingWebView: WKWebView {
    var dropHandler: ((URL) -> Void)?
    var dropStateHandler: ((FileDropState) -> Void)?
    var fileValidator: ((URL) -> Bool)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let url = droppedFileURL(from: sender) else {
            dropStateHandler?(.idle)
            return []
        }

        guard fileValidator?(url) ?? true else {
            dropStateHandler?(.invalid)
            return []
        }

        dropStateHandler?(.valid)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let url = droppedFileURL(from: sender) else {
            dropStateHandler?(.idle)
            return []
        }

        guard fileValidator?(url) ?? true else {
            dropStateHandler?(.invalid)
            return []
        }

        dropStateHandler?(.valid)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropStateHandler?(.idle)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedFileURL(from: sender) else {
            return false
        }

        return fileValidator?(url) ?? true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedFileURL(from: sender) else {
            dropStateHandler?(.idle)
            return false
        }

        guard fileValidator?(url) ?? true else {
            dropStateHandler?(.invalid)
            return false
        }

        dropStateHandler?(.idle)
        dropHandler?(url)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dropStateHandler?(.idle)
    }

    private func droppedFileURL(from sender: NSDraggingInfo) -> URL? {
        let pasteboard = sender.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        return pasteboard
            .readObjects(forClasses: [NSURL.self], options: options)?
            .compactMap { $0 as? URL }
            .first
    }
}
