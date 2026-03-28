#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_SVG="$ROOT_DIR/_assets/logo/MarkdownPreview_Icon.svg"
OUTPUT_ICNS="$ROOT_DIR/MarkdownPreview/Resources/AppIcon.icns"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/markdownpreview-icon.XXXXXX")"
PREVIEW_DIR="$TMP_DIR/preview"
ICONSET_DIR="$TMP_DIR/AppIcon.iconset"

cleanup() {
  rm -rf "$TMP_DIR"
}

fail() {
  echo "$1" >&2
  exit 1
}

trap cleanup EXIT

[[ -f "$SOURCE_SVG" ]] || fail "Missing SVG source: $SOURCE_SVG"

mkdir -p "$(dirname "$OUTPUT_ICNS")" "$PREVIEW_DIR" "$ICONSET_DIR"

if [[ -f "$OUTPUT_ICNS" && "$OUTPUT_ICNS" -nt "$SOURCE_SVG" ]]; then
  exit 0
fi

if ! qlmanage -t -s 2048 -o "$PREVIEW_DIR" "$SOURCE_SVG" >/dev/null 2>&1; then
  if [[ -f "$OUTPUT_ICNS" ]]; then
    echo "warning: failed to refresh app icon from $SOURCE_SVG; keeping existing $OUTPUT_ICNS" >&2
    exit 0
  fi

  fail "Unable to render $SOURCE_SVG into a bitmap preview with qlmanage."
fi

SOURCE_PNG="$(find "$PREVIEW_DIR" -maxdepth 1 -type f -name '*.png' -print -quit)"
[[ -n "$SOURCE_PNG" ]] || fail "qlmanage did not produce a preview PNG."

DIMENSIONS=("${(@f)$(sips -g pixelWidth -g pixelHeight "$SOURCE_PNG" | awk '/pixelWidth/ { print $2 } /pixelHeight/ { print $2 }')}")
[[ "${#DIMENSIONS[@]}" -eq 2 ]] || fail "Unable to determine preview dimensions."

WIDTH="${DIMENSIONS[1]}"
HEIGHT="${DIMENSIONS[2]}"
SQUARE_SIZE="$(( WIDTH < HEIGHT ? WIDTH : HEIGHT ))"
SQUARE_PNG="$TMP_DIR/AppIcon-square.png"

sips --cropToHeightWidth "$SQUARE_SIZE" "$SQUARE_SIZE" "$SOURCE_PNG" --out "$SQUARE_PNG" >/dev/null

make_icon() {
  local pixel_size="$1"
  local file_name="$2"

  sips -z "$pixel_size" "$pixel_size" "$SQUARE_PNG" --out "$ICONSET_DIR/$file_name" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
