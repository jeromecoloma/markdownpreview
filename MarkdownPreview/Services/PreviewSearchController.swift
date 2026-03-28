import AppKit
import Combine
import WebKit

@MainActor
final class PreviewSearchController: ObservableObject {
    @Published private(set) var canSearch = false
    @Published private(set) var hasMatches = false
    @Published private(set) var isFindPresented = false
    @Published private(set) var searchFieldFocusToken = UUID()
    @Published private(set) var searchStatusMessage: String?
    @Published private(set) var currentMatchIndex = 0
    @Published private(set) var totalMatches = 0

    var searchQuery: String {
        currentQuery
    }

    private weak var webView: WKWebView?
    private var isSearchAvailable = false
    private var currentQuery = ""
    private var keyMonitor: Any?

    init() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handleKeyEvent(event)
        }
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func register(webView: WKWebView) {
        guard self.webView !== webView else {
            refreshAvailability()
            return
        }

        self.webView = webView
        refreshAvailability()
    }

    func unregister(webView: WKWebView) {
        guard self.webView === webView else {
            return
        }

        self.webView = nil
        refreshAvailability()
    }

    func setSearchAvailable(_ isAvailable: Bool) {
        guard isSearchAvailable != isAvailable else {
            return
        }

        isSearchAvailable = isAvailable
        refreshAvailability()

        if !isAvailable {
            currentQuery = ""
            resetSearchState()
            isFindPresented = false
        }
    }

    func updateSearchQuery(_ query: String) {
        guard currentQuery != query else {
            return
        }

        currentQuery = query
        resetSearchState()

        guard isFindPresented else {
            return
        }

        setQuery()
    }

    func showFindInterface() {
        guard canSearch else {
            return
        }

        if !isFindPresented {
            isFindPresented = true
        }

        searchFieldFocusToken = UUID()
    }

    func findNext() {
        guard canSearch else {
            return
        }

        guard !normalizedQuery.isEmpty else {
            showFindInterface()
            return
        }

        isFindPresented = true
        stepSearch(backwards: false)
    }

    func findPrevious() {
        guard canSearch else {
            return
        }

        guard !normalizedQuery.isEmpty else {
            showFindInterface()
            return
        }

        isFindPresented = true
        stepSearch(backwards: true)
    }

    func hideFindInterface() {
        clearHighlights()
        resetSearchState()
        isFindPresented = false
    }

    private var normalizedQuery: String {
        currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshAvailability() {
        let nextValue = isSearchAvailable && webView != nil
        guard canSearch != nextValue else {
            return
        }

        canSearch = nextValue
    }

    private func resetSearchState() {
        hasMatches = false
        currentMatchIndex = 0
        totalMatches = 0
        searchStatusMessage = nil
    }

    private func setQuery() {
        guard canSearch, let webView else {
            return
        }

        let query = normalizedQuery
        guard !query.isEmpty else {
            clearHighlights()
            resetSearchState()
            return
        }

        runSearchScript(in: webView, operation: "setQuery", query: query)
    }

    private func stepSearch(backwards: Bool) {
        guard canSearch, let webView else {
            return
        }

        let query = normalizedQuery
        guard !query.isEmpty else {
            resetSearchState()
            return
        }

        runSearchScript(in: webView, operation: backwards ? "previous" : "next", query: query)
    }

    private func clearHighlights() {
        guard let webView else {
            return
        }

        runSearchScript(in: webView, operation: "clear", query: normalizedQuery)
    }

    private func runSearchScript(in webView: WKWebView, operation: String, query: String) {
        let queryJSON: String
        do {
            let data = try JSONSerialization.data(withJSONObject: [query])
            queryJSON = String(decoding: data, as: UTF8.self)
        } catch {
            return
        }

        let operationJSON: String
        do {
            let data = try JSONSerialization.data(withJSONObject: [operation])
            operationJSON = String(decoding: data, as: UTF8.self)
        } catch {
            return
        }

        let script = """
        (() => {
          const root = document.getElementById("markdown-root");
          if (!root) {
            return { count: 0, current: 0, found: false };
          }

          const ensureStyle = () => {
            const styleId = "md-preview-find-style";
            if (document.getElementById(styleId)) {
              return;
            }

            const style = document.createElement("style");
            style.id = styleId;
            style.textContent = `
              .md-preview-find-match {
                background: rgba(250, 204, 21, 0.35);
                border-radius: 3px;
                box-shadow: 0 0 0 1px rgba(250, 204, 21, 0.14);
              }
              .md-preview-find-match-current {
                background: rgba(245, 158, 11, 0.78);
                box-shadow: 0 0 0 1px rgba(180, 83, 9, 0.28);
              }
            `;
            document.head.appendChild(style);
          };

          const state = window.__markdownPreviewFind || (window.__markdownPreviewFind = {
            query: "",
            matches: [],
            currentIndex: -1
          });

          const result = () => ({
            count: state.matches.length,
            current: state.matches.length > 0 ? state.currentIndex + 1 : 0,
            found: state.matches.length > 0
          });

          const updateActive = () => {
            state.matches.forEach((match, index) => {
              match.classList.toggle("md-preview-find-match-current", index === state.currentIndex);
            });

            if (state.currentIndex >= 0 && state.matches[state.currentIndex]) {
              state.matches[state.currentIndex].scrollIntoView({
                block: "center",
                inline: "nearest",
                behavior: "smooth"
              });
            }
          };

          const clearMatches = () => {
            for (const match of Array.from(root.querySelectorAll("span[data-md-preview-find-match='1']"))) {
              const textNode = document.createTextNode(match.textContent || "");
              match.replaceWith(textNode);
            }
            root.normalize();
            state.matches = [];
            state.currentIndex = -1;
          };

          const collectTextNodes = () => {
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
              acceptNode(node) {
                if (!node.nodeValue || !node.nodeValue.trim()) {
                  return NodeFilter.FILTER_REJECT;
                }

                const parent = node.parentElement;
                if (!parent) {
                  return NodeFilter.FILTER_ACCEPT;
                }

                if (parent.closest("script, style")) {
                  return NodeFilter.FILTER_REJECT;
                }

                if (parent.closest("span[data-md-preview-find-match='1']")) {
                  return NodeFilter.FILTER_REJECT;
                }

                return NodeFilter.FILTER_ACCEPT;
              }
            });

            const nodes = [];
            let node = walker.nextNode();
            while (node) {
              nodes.push(node);
              node = walker.nextNode();
            }
            return nodes;
          };

          const applyQuery = (query) => {
            clearMatches();
            state.query = query;

            if (!query) {
              return result();
            }

            ensureStyle();

            const loweredQuery = query.toLocaleLowerCase();
            const queryLength = query.length;
            const nodes = collectTextNodes();

            for (const node of nodes) {
              const text = node.nodeValue || "";
              const loweredText = text.toLocaleLowerCase();
              const ranges = [];
              let searchIndex = 0;

              while (searchIndex <= loweredText.length - queryLength) {
                const matchIndex = loweredText.indexOf(loweredQuery, searchIndex);
                if (matchIndex === -1) {
                  break;
                }

                ranges.push([matchIndex, matchIndex + queryLength]);
                searchIndex = matchIndex + queryLength;
              }

              if (ranges.length === 0) {
                continue;
              }

              const fragment = document.createDocumentFragment();
              let lastIndex = 0;

              for (const [start, end] of ranges) {
                if (start > lastIndex) {
                  fragment.appendChild(document.createTextNode(text.slice(lastIndex, start)));
                }

                const span = document.createElement("span");
                span.dataset.mdPreviewFindMatch = "1";
                span.className = "md-preview-find-match";
                span.textContent = text.slice(start, end);
                fragment.appendChild(span);
                lastIndex = end;
              }

              if (lastIndex < text.length) {
                fragment.appendChild(document.createTextNode(text.slice(lastIndex)));
              }

              node.replaceWith(fragment);
            }

            state.matches = Array.from(root.querySelectorAll("span[data-md-preview-find-match='1']"));
            state.currentIndex = state.matches.length > 0 ? 0 : -1;
            updateActive();
            return result();
          };

          const step = (direction) => {
            if (state.query !== query) {
              applyQuery(query);
            }

            if (state.matches.length === 0) {
              return result();
            }

            const delta = direction === "previous" ? -1 : 1;
            state.currentIndex = (state.currentIndex + delta + state.matches.length) % state.matches.length;
            updateActive();
            return result();
          };

          const query = \(queryJSON)[0].trim();
          const operation = \(operationJSON)[0];

          if (operation === "clear") {
            clearMatches();
            state.query = "";
            return result();
          }

          if (operation === "setQuery") {
            return applyQuery(query);
          }

          return step(operation);
        })();
        """

        let normalizedQuery = normalizedQuery
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else {
                return
            }

            guard self.normalizedQuery == normalizedQuery else {
                return
            }

            guard let state = result as? [String: Any] else {
                self.resetSearchState()
                self.searchStatusMessage = "Search unavailable"
                return
            }

            let total = state["count"] as? Int ?? 0
            let current = state["current"] as? Int ?? 0
            let found = state["found"] as? Bool ?? false

            self.totalMatches = total
            self.currentMatchIndex = current
            self.hasMatches = found
            self.searchStatusMessage = found ? nil : (normalizedQuery.isEmpty ? nil : "No matches")
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard canSearch else {
            return event
        }

        guard event.type == .keyDown else {
            return event
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if isFindPresented && (event.keyCode == 36 || event.keyCode == 76) {
            switch flags {
            case []:
                findNext()
                return nil
            case [.shift]:
                findPrevious()
                return nil
            default:
                break
            }
        }

        guard flags == [.command] || flags == [.command, .shift] else {
            return event
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "f" where flags == [.command]:
            showFindInterface()
            return nil
        case "g" where flags == [.command]:
            findNext()
            return nil
        case "g" where flags == [.command, .shift]:
            findPrevious()
            return nil
        default:
            return event
        }
    }
}
