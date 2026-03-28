#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/DerivedData/Build/Products/Debug/MarkdownPreview.app"

if [[ ! -d "$APP_PATH" ]]; then
  "$ROOT_DIR/scripts/build.sh"
fi

open "$APP_PATH"
