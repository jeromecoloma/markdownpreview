# MarkdownPreview

[![Build](https://github.com/jeromecoloma/markdownpreview/actions/workflows/build.yml/badge.svg)](https://github.com/jeromecoloma/markdownpreview/actions/workflows/build.yml)

A minimal native macOS Markdown reader built with SwiftUI and WKWebView.

**Requires macOS 13 Ventura or later.**

---

## Features

- Open `.md` files from the sidebar button, by dragging them into the window, or from Finder via `Open With`
- Render GitHub-flavored Markdown with offline syntax highlighting and Mermaid diagram support
- Search the loaded document with standard macOS find controls (`Command-F`, `Command-G`, `Shift-Command-G`)
- Live reload when the underlying file changes on disk
- Persist the 20 most recent files with security-scoped bookmarks
- Remove stale recent items directly from the sidebar
- Unsupported files are rejected with clear inline feedback

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Command-O` | Open a Markdown file |
| `Command-R` | Reload the current file |
| `Command-F` | Open Find |
| `Command-G` | Next match |
| `Shift-Command-G` | Previous match |

## Build from Source

**Requirements:** macOS 13+, Xcode 15+

```bash
git clone https://github.com/jeromecoloma/markdownpreview.git
cd markdownpreview
./scripts/build.sh
```

The built app is placed in `dist/DerivedData`. Move it to `/Applications` to register it as a Finder viewer for `.md` files.

To set it as the default viewer: in Finder, `Get Info` on any `.md` file → `Open with` → select `MarkdownPreview` → `Change All…`

The app icon is generated from `_assets/logo/MarkdownPreview_Icon.svg` during the Xcode build phase.

## Project Status

Active — personal project maintained on a best-effort basis. Bug reports and small contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Changelog

See [docs/CHANGELOG.md](docs/CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).
