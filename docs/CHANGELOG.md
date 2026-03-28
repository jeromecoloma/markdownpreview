# Changelog

## Unreleased

- Re-added Mermaid syntax support in the web preview, including offline rendering
- Fixed reload-triggered cases that incorrectly fell back from the web preview
- Improved the sidebar with selection animation, hover states, and safer filename layout
- Fixed drag-and-drop handling while another file is already open
- Restricted opening and drag-and-drop to `.md` files, with clearer unsupported-file feedback
- Added recent file removal directly from the sidebar and context menu
- Added a preview loading overlay so long renders surface visible progress
- Added in-document search with `Command-F`, `Command-G`, and `Shift-Command-G`
- Registered the app as a Finder viewer for Markdown files when the built app is installed
- Added `Command-R` to reload the current file manually

## 0.1.0

- Initial app scaffold
- Split-view UI with recent files sidebar
- Native Markdown preview fallback for reliable file rendering
- Security-scoped bookmark persistence
- Live file watching with debounced reloads
- Bundled offline web assets and experimental `WKWebView` preview pipeline

## Known Limitations

- Only `.md` files are supported
- In-document search is available in the web preview path and is unavailable while the native fallback is active
