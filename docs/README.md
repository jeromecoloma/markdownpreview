# MarkdownPreview

Minimal native macOS Markdown reader built with SwiftUI and `WKWebView`.

## Current Scope

- Open Markdown files from the sidebar button or by dragging them into the window
- Open Markdown files from Finder via `Open With` once the app bundle is built and installed
- Render GitHub-flavored Markdown inside a native split-view shell
- Render Mermaid diagrams and syntax-highlighted code fully offline
- Persist the 20 most recent files with security-scoped bookmarks
- Live reload when the underlying file changes on disk

## Build

```bash
./scripts/build.sh
```

The app icon is generated from the SVG source at `_assets/logo/MarkdownPreview_Icon.svg` during the Xcode build and bundled as `AppIcon.icns`.

After moving the built app into `/Applications`, macOS can list it as a viewer for `.md` files. To make it the default viewer, use Finder's `Get Info` panel on a Markdown file, choose `MarkdownPreview` under `Open with`, then click `Change All…`.
