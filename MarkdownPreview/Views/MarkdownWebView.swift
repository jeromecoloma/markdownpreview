import AppKit
import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let fileURL: URL?
    let onDiagnostics: @MainActor (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDiagnostics: onDiagnostics)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onDiagnostics = onDiagnostics

        guard
            context.coordinator.lastHTML != html ||
            context.coordinator.lastBaseURL != baseURL ||
            context.coordinator.lastFileURL != fileURL
        else {
            return
        }

        context.coordinator.lastHTML = html
        context.coordinator.lastBaseURL = baseURL
        context.coordinator.lastFileURL = fileURL
        context.coordinator.report("Loading preview…")

        if let fileURL {
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""
        var lastBaseURL: URL?
        var lastFileURL: URL?
        var onDiagnostics: @MainActor (String?) -> Void

        init(onDiagnostics: @escaping @MainActor (String?) -> Void) {
            self.onDiagnostics = onDiagnostics
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            report("Starting web preview…")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.getElementById('markdown-root')?.innerText?.trim()?.slice(0, 120) ?? ''") { [weak self] result, _ in
                if let text = result as? String, !text.isEmpty {
                    self?.report(nil)
                } else {
                    self?.report("Preview loaded, but no rendered content was detected.")
                }
            }
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
