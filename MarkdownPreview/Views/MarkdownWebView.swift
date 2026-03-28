import AppKit
import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let fileURL: URL?
    let requestID: UUID
    let onDiagnostics: @MainActor (String?) -> Void

    private let topContentInset: CGFloat = 20

    func makeCoordinator() -> Coordinator {
        Coordinator(onDiagnostics: onDiagnostics)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        configureScrollViewIfNeeded(for: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onDiagnostics = onDiagnostics
        context.coordinator.topContentInset = topContentInset
        configureScrollViewIfNeeded(for: webView)

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
        context.coordinator.report("Loading preview…")

        if let fileURL {
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(html, baseURL: baseURL)
        }
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
        var onDiagnostics: @MainActor (String?) -> Void
        var topContentInset: CGFloat = 20

        init(onDiagnostics: @escaping @MainActor (String?) -> Void) {
            self.onDiagnostics = onDiagnostics
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            report("Starting web preview…")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            resetScrollPosition(in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report("Navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report("Preview failed to start: \(error.localizedDescription)")
        }

        func report(_ message: String?) {
            Task { @MainActor in
                onDiagnostics(message)
            }
        }

        private func resetScrollPosition(in webView: WKWebView) {
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
              return document.getElementById('markdown-root')?.innerText?.trim()?.slice(0, 120) ?? '';
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] result, _ in
                if let text = result as? String, !text.isEmpty {
                    self?.report(nil)
                } else {
                    self?.report("Preview loaded, but no rendered content was detected.")
                }
            }
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
