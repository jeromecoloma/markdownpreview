#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MarkdownPreview/MarkdownPreview.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/dist/DerivedData"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme MarkdownPreview \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build
