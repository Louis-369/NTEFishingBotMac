#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$ROOT/app"
ARCH="${MAC_FISHING_BOT_ARCH:-$(uname -m)}"
BUILD_DIR="$ROOT/.build/app"
APP_DIR="$ROOT/dist/MacFishingBotControl.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
MODULE_CACHE="$BUILD_DIR/module-cache"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES" "$MODULE_CACHE"

swiftc \
  -target "${ARCH}-apple-macosx14.0" \
  -O \
  -D LIBRARY_MODE \
  -parse-as-library \
  -module-cache-path "$MODULE_CACHE" \
  -o "$MACOS/MacFishingBotControl" \
  "$ROOT/cli/Sources/MacFishingBot/main.swift" \
  "$APP_ROOT"/Sources/App/*.swift \
  "$APP_ROOT"/Sources/Models/*.swift \
  "$APP_ROOT"/Sources/Stores/*.swift \
  "$APP_ROOT"/Sources/Services/*.swift \
  "$APP_ROOT"/Sources/Support/*.swift \
  "$APP_ROOT"/Sources/Views/*.swift \
  -framework SwiftUI \
  -framework AppKit \
  -framework ApplicationServices \
  -framework CoreGraphics \
  -framework ImageIO \
  -framework UniformTypeIdentifiers

cp "$APP_ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/cli/sample-fish-config.json" "$RESOURCES/sample-fish-config.json"
chmod +x "$MACOS/MacFishingBotControl"

if [[ -n "${MAC_FISHING_BOT_SIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --sign "$MAC_FISHING_BOT_SIGN_IDENTITY" "$APP_DIR" >/dev/null
else
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
