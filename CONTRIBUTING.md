# Contributing to MarkdownPreview

Thanks for your interest. This is a personal project maintained on a best-effort basis.

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later

## Setup

```bash
git clone https://github.com/jeromecoloma/markdownpreview.git
cd markdownpreview
```

Open `MarkdownPreview/MarkdownPreview.xcodeproj` in Xcode, or build from the command line:

```bash
./scripts/build.sh
```

### Bundled web assets

The app bundles `marked.js`, `mermaid.js`, `highlight.js`, and their associated CSS files. To regenerate them from upstream:

```bash
./scripts/fetch_assets.sh
```

Avoid committing manual edits to the bundled JS/CSS files — regenerate them instead.

## Submitting changes

1. Fork the repo and create a branch from `main`
2. Make your changes and verify the app builds cleanly
3. Open a pull request against `main` with a clear description of what changed and why

## What's welcome

- Bug fixes
- Documentation improvements
- Minor UX polish

## What to discuss first

For anything beyond a targeted bug fix — new features, scope changes, architectural refactors — please open an issue first. This avoids wasted effort if the change falls outside the project's intended scope.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
