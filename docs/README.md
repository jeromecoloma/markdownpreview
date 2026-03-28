# MarkdownPreview

Minimal native macOS Markdown reader built with SwiftUI and `WKWebView`.

## Current Scope

- Open `.md` files from the sidebar button, by dragging them into the window, or from Finder via `Open With`
- Reject unsupported files with clear inline and alert feedback
- Render GitHub-flavored Markdown inside a native split-view shell
- Render Mermaid diagrams and syntax-highlighted code fully offline
- Search the loaded document with in-preview find controls and standard macOS shortcuts
- Persist the 20 most recent files with security-scoped bookmarks
- Remove stale recent items directly from the sidebar
- Live reload when the underlying file changes on disk, with a manual reload command when needed

## Keyboard Shortcuts

- `Command-F` opens Find
- `Command-G` jumps to the next search match
- `Shift-Command-G` jumps to the previous search match
- `Command-R` reloads the current Markdown file

## Build

```bash
./scripts/build.sh
```

The app icon is generated from the SVG source at `_assets/logo/MarkdownPreview_Icon.svg` during the Xcode build and bundled as `AppIcon.icns`.

After moving the built app into `/Applications`, macOS can list it as a viewer for `.md` files. To make it the default viewer, use Finder's `Get Info` panel on a Markdown file, choose `MarkdownPreview` under `Open with`, then click `Change All…`.
