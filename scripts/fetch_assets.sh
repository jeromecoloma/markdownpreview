#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCE_DIR="$ROOT_DIR/MarkdownPreview/Resources"

curl -L --fail https://raw.githubusercontent.com/sindresorhus/github-markdown-css/main/github-markdown.css -o "$RESOURCE_DIR/github-markdown.css"
curl -L --fail https://raw.githubusercontent.com/highlightjs/highlight.js/main/src/styles/github.css -o "$RESOURCE_DIR/highlight-github.css"
curl -L --fail https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@latest/build/highlight.min.js -o "$RESOURCE_DIR/highlight.min.js"
curl -L --fail https://cdn.jsdelivr.net/npm/marked/lib/marked.umd.js -o "$RESOURCE_DIR/marked.min.js"
curl -L --fail https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js -o "$RESOURCE_DIR/mermaid.min.js"
