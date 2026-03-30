import Foundation
import JavaScriptCore

struct MarkdownRenderer {
    struct RenderedDocument {
        let html: String
        let baseURL: URL?
        let fileURL: URL
    }

    private struct BundledAssets {
        let markdownCSS: String
        let highlightCSS: String
        let highlightJS: String
        let markedJS: String
        let mermaidJS: String
    }

    private final class MarkdownHTMLParser {
        private let context: JSContext

        init(markedSource: String) throws {
            guard let context = JSContext() else {
                throw RendererError.unreadableBundledAsset("marked.min.js")
            }

            self.context = context
            context.evaluateScript(markedSource)

            if let exception = context.exception?.toString() {
                throw ParserError.javaScript(exception)
            }
        }

        func render(markdown: String) throws -> String {
            context.exception = nil
            context.setObject(markdown, forKeyedSubscript: "__markdownSource" as NSString)

            let result = context.evaluateScript(
                """
                marked.parse(__markdownSource, {
                  gfm: true,
                  breaks: false
                });
                """
            )

            if let exception = context.exception?.toString() {
                throw ParserError.javaScript(exception)
            }

            guard let html = result?.toString() else {
                throw ParserError.noOutput
            }

            return html
        }
    }

    private enum ParserError: LocalizedError {
        case javaScript(String)
        case noOutput

        var errorDescription: String? {
            switch self {
            case .javaScript(let message):
                return "Markdown parsing failed: \(message)"
            case .noOutput:
                return "Markdown parsing returned no HTML."
            }
        }
    }

    enum RendererError: LocalizedError {
        case missingResourceRoot
        case missingBundledAsset(String)
        case unreadableBundledAsset(String)

        var errorDescription: String? {
            switch self {
            case .missingResourceRoot:
                return "The bundled web resources could not be found."
            case .missingBundledAsset(let assetName):
                return "The bundled asset \(assetName) is missing."
            case .unreadableBundledAsset(let assetName):
                return "The bundled asset \(assetName) could not be read."
            }
        }
    }

    private static let cachedAssets: Result<BundledAssets, Error> = {
        do {
            return .success(try loadBundledAssets())
        } catch {
            return .failure(error)
        }
    }()

    private static let cachedParser: Result<MarkdownHTMLParser, Error> = {
        do {
            let assets = try cachedAssets.get()
            return .success(try MarkdownHTMLParser(markedSource: assets.markedJS))
        } catch {
            return .failure(error)
        }
    }()

    func render(markdown: String, title: String, documentURL: URL) throws -> RenderedDocument {
        guard Bundle.main.resourceURL != nil else {
            throw RendererError.missingResourceRoot
        }

        let bundledAssets = try Self.cachedAssets.get()
        let parser = try Self.cachedParser.get()
        let renderedMarkdownHTML = try parser.render(markdown: markdown)
        let titleLiteral = escapeHTML(title)
        let markdownCSS = inlineStyleLiteral(for: bundledAssets.markdownCSS)
        let highlightCSS = inlineStyleLiteral(for: bundledAssets.highlightCSS)
        let highlightJS = inlineScriptLiteral(for: bundledAssets.highlightJS)
        let mermaidJS = inlineScriptLiteral(for: bundledAssets.mermaidJS)
        let renderedBody = renderedMarkdownHTML.replacingOccurrences(of: "</script", with: "<\\/script")

        let html = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(titleLiteral)</title>
          <style>
            \(markdownCSS)
          </style>
          <style>
            \(highlightCSS)
          </style>
          <style>
            :root {
              color-scheme: light dark;
            }

            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
            }

            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            }

            .page {
              min-height: 100vh;
              padding: 24px 32px 48px;
              box-sizing: border-box;
            }

            .markdown-body {
              box-sizing: border-box;
              min-width: 200px;
              max-width: 980px;
              margin: 0 auto;
              padding: 32px 40px 56px;
              border-radius: 20px;
              background: color-mix(in srgb, Canvas 92%, transparent);
              box-shadow: 0 18px 40px rgba(15, 23, 42, 0.08);
            }

            .markdown-body pre {
              overflow-x: auto;
            }

            .markdown-body .mermaid {
              display: flex;
              justify-content: center;
              overflow-x: auto;
              padding: 16px 0;
            }

            @media (prefers-color-scheme: dark) {
              .markdown-body {
                background: color-mix(in srgb, #0f172a 88%, transparent);
                box-shadow: 0 20px 48px rgba(2, 6, 23, 0.42);
              }
            }

            @media (max-width: 860px) {
              .page {
                padding: 16px;
              }

              .markdown-body {
                padding: 24px 20px 40px;
              }
            }
          </style>
        </head>
        <body>
          <div class="page">
            <article id="markdown-root" class="markdown-body">\(renderedBody)</article>
          </div>
          <script>
            \(highlightJS)
          </script>
          <script>
            \(mermaidJS)
          </script>
          <script>
            (() => {
              const root = document.getElementById("markdown-root");
              if (!root) {
                return;
              }

              const mermaidQuery = window.matchMedia?.("(prefers-color-scheme: dark)") ?? null;
              const mermaidSelector = "pre > code.language-mermaid, pre > code.lang-mermaid";
              for (const codeBlock of root.querySelectorAll(mermaidSelector)) {
                const pre = codeBlock.parentElement;
                if (!pre) {
                  continue;
                }

                const mermaidContainer = document.createElement("div");
                mermaidContainer.className = "mermaid";
                mermaidContainer.dataset.source = codeBlock.textContent ?? "";
                mermaidContainer.textContent = mermaidContainer.dataset.source;
                pre.replaceWith(mermaidContainer);
              }

              if (window.hljs) {
                for (const codeBlock of root.querySelectorAll("pre code")) {
                  window.hljs.highlightElement(codeBlock);
                }
              }

              const renderMermaid = () => {
                if (!window.mermaid) {
                  return;
                }

                const prefersDark = mermaidQuery?.matches ?? false;
                window.mermaid.initialize({
                  startOnLoad: false,
                  securityLevel: "loose",
                  theme: prefersDark ? "dark" : "default"
                });

                for (const diagram of root.querySelectorAll(".mermaid")) {
                  diagram.removeAttribute("data-processed");
                  diagram.innerHTML = "";
                  diagram.textContent = diagram.dataset.source ?? "";
                }

                window.mermaid.run({
                  querySelector: "#markdown-root .mermaid",
                  suppressErrors: true
                });
              };

              renderMermaid();

              if (mermaidQuery) {
                const rerender = () => renderMermaid();

                if (typeof mermaidQuery.addEventListener === "function") {
                  mermaidQuery.addEventListener("change", rerender);
                } else if (typeof mermaidQuery.addListener === "function") {
                  mermaidQuery.addListener(rerender);
                }
              }
            })();
          </script>
        </body>
        </html>
        """

        let fileURL = try writeHTMLToTemporaryLocation(html: html, title: title)
        return RenderedDocument(html: html, baseURL: nil, fileURL: fileURL)
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func inlineStyleLiteral(for value: String) -> String {
        value.replacingOccurrences(of: "</style", with: "<\\/style")
    }

    private func inlineScriptLiteral(for value: String) -> String {
        value.replacingOccurrences(of: "</script", with: "<\\/script")
    }

    private static func loadBundledAssets() throws -> BundledAssets {
        BundledAssets(
            markdownCSS: try loadResource(named: "github-markdown", withExtension: "css"),
            highlightCSS: try loadResource(named: "highlight-github", withExtension: "css"),
            highlightJS: try loadResource(named: "highlight.min", withExtension: "js"),
            markedJS: try loadResource(named: "marked.min", withExtension: "js"),
            mermaidJS: try loadResource(named: "mermaid.min", withExtension: "js")
        )
    }

    private static func loadResource(named name: String, withExtension ext: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw RendererError.missingBundledAsset("\(name).\(ext)")
        }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw RendererError.unreadableBundledAsset("\(name).\(ext)")
        }

        return contents
    }

    private func writeHTMLToTemporaryLocation(html: String, title: String) throws -> URL {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownPreview", isDirectory: true)

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let safeTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileURL = tempRoot.appendingPathComponent("\(safeTitle)-preview.html")

        try html.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
