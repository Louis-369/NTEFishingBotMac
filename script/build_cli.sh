#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${MAC_FISHING_BOT_ARCH:-$(uname -m)}"
MODULE_CACHE="$ROOT/.build/clang-module-cache"
DIST_DIR="$ROOT/dist/mac-fishing-bot"
BIN_DIR="$DIST_DIR/bin"

rm -rf "$DIST_DIR"
mkdir -p "$BIN_DIR" "$DIST_DIR/samples" "$DIST_DIR/templates" "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
  -target "${ARCH}-apple-macosx14.0" \
  -O \
  -parse-as-library \
  -o "$BIN_DIR/mac-fishing-bot" \
  "$ROOT/cli/Sources/MacFishingBot/main.swift" \
  "$ROOT/cli/Sources/MacFishingBot/CLIEntry.swift" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework CoreGraphics \
  -framework ImageIO \
  -framework UniformTypeIdentifiers

cp "$ROOT/cli/sample-config.json" "$DIST_DIR/sample-config.json"
cp "$ROOT/cli/sample-fish-config.json" "$DIST_DIR/sample-fish-config.json"

echo "$BIN_DIR/mac-fishing-bot"
