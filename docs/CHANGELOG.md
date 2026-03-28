# Changelog

## 0.1.0

- Initial app scaffold
- Split-view UI with recent files sidebar
- Native Markdown preview fallback for reliable file rendering
- Security-scoped bookmark persistence
- Live file watching with debounced reloads
- Bundled offline web assets and experimental `WKWebView` preview pipeline

## Known Limitations

- Mermaid rendering is not working reliably yet and should be considered unsupported in the current build
- The rich `WKWebView` preview path is still under investigation; the app currently relies on the native Markdown fallback when the web preview stalls
